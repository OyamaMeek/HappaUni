import Foundation

struct SyncRemoteDocument: Equatable {
    let documentID: UUID
    let filename: String
    let sha: String
    let path: String

    init(path: String, sha: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard components.count >= 3,
              components[0] == "documents",
              let id = UUID(uuidString: components[1]) else {
            throw SyncError.invalidRemotePath
        }
        documentID = id
        filename = components.dropFirst(2).joined(separator: "/")
        self.sha = sha
        self.path = path
    }
}

struct SyncConflict: Identifiable, Equatable {
    let documentID: UUID
    let name: String
    let remoteSHA: String
    var id: UUID { documentID }
}

struct RestoreSummary: Equatable {
    let restored: [LibraryDocument]
    let conflicts: [SyncConflict]
}

enum LibraryRemotePath {
    static let unfiledDirectory = "未归档"
    static let trashDirectory = "废纸篓"
    static let manifestPath = ".happauni-library.json"

    static func documentPath(for document: LibraryDocument, folders: [LibraryFolder]) -> String {
        if document.isInTrash {
            return [trashDirectory, safeComponent(document.name)].joined(separator: "/")
        }
        let directory = folderComponents(for: document.folderID, folders: folders).joined(separator: "/")
        return [directory, safeComponent(document.name)].joined(separator: "/")
    }

    static func annotationPath(for document: LibraryDocument, folders: [LibraryFolder]) -> String {
        let documentPath = documentPath(for: document, folders: folders)
        let directory = (documentPath as NSString).deletingLastPathComponent
        let filename = ".\(document.id.uuidString).happauni-annotations"
        return directory.isEmpty ? filename : "\(directory)/\(filename)"
    }

    private static func folderComponents(for folderID: UUID?, folders: [LibraryFolder]) -> [String] {
        guard let folderID else { return [unfiledDirectory] }
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var components: [String] = []
        var cursor = foldersByID[folderID]
        var visited = Set<UUID>()

        while let folder = cursor, visited.insert(folder.id).inserted {
            components.insert(safeComponent(folder.name), at: 0)
            cursor = folder.parentID.flatMap { foldersByID[$0] }
        }
        return components.isEmpty ? [unfiledDirectory] : components
    }

    private static func safeComponent(_ value: String) -> String {
        let component = URL(fileURLWithPath: value).lastPathComponent
        return component.isEmpty || component == "." ? "未命名" : component
    }
}

struct LibraryBackupManifest: Codable, Equatable {
    static let path = LibraryRemotePath.manifestPath
    static let legacyPath = "metadata/library.json"

    struct Document: Codable, Equatable {
        let id: UUID
        let tags: [String]
        let folderID: UUID?
        let isFavorite: Bool
        let createdAt: Date
        let modifiedAt: Date
        let trashedAt: Date?
        let name: String?
        let remotePath: String?

        init(_ document: LibraryDocument, folders: [LibraryFolder]) {
            id = document.id
            tags = document.tags
            folderID = document.folderID
            isFavorite = document.isFavorite
            createdAt = document.createdAt
            modifiedAt = document.modifiedAt
            trashedAt = document.trashedAt
            name = document.name
            remotePath = LibraryRemotePath.documentPath(for: document, folders: folders)
        }
    }

    struct Folder: Codable, Equatable {
        let id: UUID
        let name: String
        let parentID: UUID?
        let createdAt: Date

        init(_ folder: LibraryFolder) {
            id = folder.id
            name = folder.name
            parentID = folder.parentID
            createdAt = folder.createdAt
        }
    }

    let schemaVersion: Int
    let exportedAt: Date
    let documents: [Document]
    let folders: [Folder]

    init(documents: [LibraryDocument], folders: [LibraryFolder], exportedAt: Date = .now) {
        schemaVersion = 3
        self.exportedAt = exportedAt
        self.documents = documents.map { Document($0, folders: folders) }
        self.folders = folders.map(Folder.init)
    }
}

enum WebDAVBackupSettings {
    static let enabledKey = "webDAVBackupEnabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }
}

enum SyncError: LocalizedError {
    case notAuthenticated
    case invalidRemotePath

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "未登录 GitHub。"
        case .invalidRemotePath: "GitHub 仓库中存在无法识别的同步文件。"
        }
    }
}

final class SyncService {
    static let shared = SyncService()

    func syncFileOnOpen(
        _ document: LibraryDocument,
        folders: [LibraryFolder],
        repository: String = GitHubConfiguration.default.repositoryName,
        force: Bool = false
    ) async throws {
        guard GitHubService.shared.isAuthenticated else { return }
        let fileModifiedAt = (
            try? FileManager.default.attributesOfItem(atPath: document.url.path)[.modificationDate] as? Date
        ) ?? .distantPast
        let localModifiedAt = max(document.modifiedAt, fileModifiedAt)
        guard force || !document.isSyncedToGitHub || localModifiedAt > (document.gitLastSyncAt ?? .distantPast) else { return }

        let data = try Data(contentsOf: document.url)
        let path = LibraryRemotePath.documentPath(for: document, folders: folders)
        let sha = try await GitHubService.shared.commit(data: data, repository: repository, path: path, message: "Sync \(document.name)")
        if let annotationData = PDFAnnotationStore.archiveData(for: document.url) {
            _ = try await GitHubService.shared.commit(
                data: annotationData,
                repository: repository,
                path: LibraryRemotePath.annotationPath(for: document, folders: folders),
                message: "Sync annotations for \(document.name)"
            )
        }
        document.isSyncedToGitHub = true
        document.gitCommitHash = sha
        document.gitLastSyncAt = .now
    }

    func syncEditedDocument(
        _ document: LibraryDocument,
        documents: [LibraryDocument],
        folders: [LibraryFolder],
        webDAVAccounts: [WebDAVAccount],
        repository: String = GitHubConfiguration.default.repositoryName
    ) async {
        do {
            try await syncFileOnOpen(document, folders: folders, repository: repository, force: true)
            try await backupMetadata(documents: documents, folders: folders, repository: repository)
        } catch {
            // WebDAV synchronization below remains available when GitHub is offline.
        }

        guard WebDAVBackupSettings.isEnabled, !document.isInTrash else { return }
        for account in webDAVAccounts {
            try? await upload(document, folders: folders, to: account)
        }
    }

    private func upload(_ document: LibraryDocument, folders: [LibraryFolder], to account: WebDAVAccount) async throws {
        guard
            let serverURL = account.serverURL,
            let password = try KeychainStore().value(for: account.passwordKey)
        else {
            return
        }

        let relativePath = LibraryRemotePath.documentPath(for: document, folders: folders)
        let documentRemotePath = WebDAVRemotePath.join(base: WebDAVRemotePath.libraryRoot, child: relativePath)
        let documentDirectory = WebDAVRemotePath.parent(of: documentRemotePath)
        try await ensureDirectoryTree(at: documentDirectory, serverURL: serverURL, username: account.username, password: password)

        do {
            try await WebDAVService.shared.upload(
                data: Data(contentsOf: document.url),
                to: WebDAVRemotePath.url(serverURL: serverURL, path: documentRemotePath),
                username: account.username,
                password: password
            )
        } catch {
            WebDAVUploadQueue.shared.enqueue(accountID: account.id, localURL: document.url, remotePath: documentRemotePath)
            throw error
        }

        guard let annotationData = PDFAnnotationStore.archiveData(for: document.url) else { return }
        let annotationRemotePath = WebDAVRemotePath.join(
            base: WebDAVRemotePath.libraryRoot,
            child: LibraryRemotePath.annotationPath(for: document, folders: folders)
        )
        try await WebDAVService.shared.upload(
            data: annotationData,
            to: WebDAVRemotePath.url(serverURL: serverURL, path: annotationRemotePath),
            username: account.username,
            password: password
        )
    }

    private func ensureDirectoryTree(at path: String, serverURL: URL, username: String, password: String) async throws {
        var currentPath = ""
        for component in path.split(separator: "/") {
            currentPath = WebDAVRemotePath.join(base: currentPath, child: String(component))
            try await WebDAVService.shared.ensureDirectory(serverURL: serverURL, username: username, password: password, path: currentPath)
        }
    }

    func restoreDocuments(repository: String, existingDocuments: [LibraryDocument]) async throws -> RestoreSummary {
        guard GitHubService.shared.isAuthenticated else { throw SyncError.notAuthenticated }
        let existingByID = Dictionary(uniqueKeysWithValues: existingDocuments.map { ($0.id, $0) })
        let manifest = try await restoreMetadata(repository: repository)
        var restored: [LibraryDocument] = []
        var conflicts: [SyncConflict] = []

        if let manifest {
            for metadata in manifest.documents {
                guard let filename = metadata.name, let path = metadata.remotePath else { continue }
                if let local = existingByID[metadata.id] {
                    if local.modifiedAt > (local.gitLastSyncAt ?? .distantPast) {
                        conflicts.append(SyncConflict(documentID: local.id, name: local.name, remoteSHA: local.gitCommitHash ?? ""))
                    }
                    continue
                }
                let data = try await GitHubService.shared.download(repository: repository, path: path)
                restored.append(try FileService().restoreDocument(data: data, filename: filename, id: metadata.id, gitSHA: "backup"))
            }
            return RestoreSummary(restored: restored, conflicts: conflicts)
        }

        let remoteFiles = try await GitHubService.shared.listSyncedDocuments(repository: repository)
        for remoteFile in remoteFiles {
            let remote = try SyncRemoteDocument(path: remoteFile.path, sha: remoteFile.sha)
            if let local = existingByID[remote.documentID] {
                let localChanged = local.modifiedAt > (local.gitLastSyncAt ?? .distantPast)
                if localChanged && local.gitCommitHash != remote.sha {
                    conflicts.append(SyncConflict(documentID: local.id, name: local.name, remoteSHA: remote.sha))
                }
                continue
            }
            let data = try await GitHubService.shared.download(repository: repository, path: remote.path)
            restored.append(try FileService().restoreDocument(data: data, filename: remote.filename, id: remote.documentID, gitSHA: remote.sha))
        }
        return RestoreSummary(restored: restored, conflicts: conflicts)
    }

    func backupMetadata(documents: [LibraryDocument], folders: [LibraryFolder], repository: String) async throws {
        guard GitHubService.shared.isAuthenticated else { throw SyncError.notAuthenticated }
        let manifest = LibraryBackupManifest(documents: documents, folders: folders)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        _ = try await GitHubService.shared.commit(data: data, repository: repository, path: LibraryBackupManifest.path, message: "Backup library metadata")
    }

    func restoreMetadata(repository: String) async throws -> LibraryBackupManifest? {
        guard GitHubService.shared.isAuthenticated else { throw SyncError.notAuthenticated }
        let primaryData = try await GitHubService.shared.downloadIfExists(
            repository: repository,
            path: LibraryBackupManifest.path
        )
        let data = try await (primaryData == nil
            ? GitHubService.shared.downloadIfExists(repository: repository, path: LibraryBackupManifest.legacyPath)
            : primaryData)
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LibraryBackupManifest.self, from: data)
    }

    func apply(_ manifest: LibraryBackupManifest, to documents: [LibraryDocument]) {
        let metadataByID = Dictionary(uniqueKeysWithValues: manifest.documents.map { ($0.id, $0) })
        for document in documents {
            guard let metadata = metadataByID[document.id] else { continue }
            document.tags = metadata.tags
            document.folderID = metadata.folderID
            document.isFavorite = metadata.isFavorite
            document.trashedAt = metadata.trashedAt
        }
    }
}
