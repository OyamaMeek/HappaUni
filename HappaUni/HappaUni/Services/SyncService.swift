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
        self.documentID = id
        self.filename = components.dropFirst(2).joined(separator: "/")
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

struct LibraryBackupManifest: Codable, Equatable {
    static let path = "metadata/library.json"

    struct Document: Codable, Equatable {
        let id: UUID
        let tags: [String]
        let folderID: UUID?
        let isFavorite: Bool
        let createdAt: Date
        let modifiedAt: Date

        init(_ document: LibraryDocument) {
            id = document.id
            tags = document.tags
            folderID = document.folderID
            isFavorite = document.isFavorite
            createdAt = document.createdAt
            modifiedAt = document.modifiedAt
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
        schemaVersion = 1
        self.exportedAt = exportedAt
        self.documents = documents.map(Document.init)
        self.folders = folders.map(Folder.init)
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

    func syncFileOnOpen(_ document: LibraryDocument, repository: String = GitHubConfiguration.default.repositoryName) async throws {
        guard GitHubService.shared.isAuthenticated else { return }
        guard !document.isSyncedToGitHub || document.modifiedAt > (document.gitLastSyncAt ?? .distantPast) else { return }
        let data = try Data(contentsOf: document.url)
        let path = "documents/\(document.id.uuidString)/\(document.name)"
        let sha = try await GitHubService.shared.commit(data: data, repository: repository, path: path, message: "Sync \(document.name)")
        document.isSyncedToGitHub = true
        document.gitCommitHash = sha
        document.gitLastSyncAt = .now
    }

    func restoreDocuments(
        repository: String,
        existingDocuments: [LibraryDocument]
    ) async throws -> RestoreSummary {
        guard GitHubService.shared.isAuthenticated else { throw SyncError.notAuthenticated }
        let remoteFiles = try await GitHubService.shared.listSyncedDocuments(repository: repository)
        let existingByID = Dictionary(uniqueKeysWithValues: existingDocuments.map { ($0.id, $0) })
        var restored: [LibraryDocument] = []
        var conflicts: [SyncConflict] = []

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
            let document = try FileService().restoreDocument(data: data, filename: remote.filename, id: remote.documentID, gitSHA: remote.sha)
            restored.append(document)
        }
        return RestoreSummary(restored: restored, conflicts: conflicts)
    }

    func backupMetadata(
        documents: [LibraryDocument],
        folders: [LibraryFolder],
        repository: String
    ) async throws {
        guard GitHubService.shared.isAuthenticated else { throw SyncError.notAuthenticated }
        let manifest = LibraryBackupManifest(documents: documents, folders: folders)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        _ = try await GitHubService.shared.commit(
            data: data,
            repository: repository,
            path: LibraryBackupManifest.path,
            message: "Backup library metadata"
        )
    }

    func restoreMetadata(repository: String) async throws -> LibraryBackupManifest? {
        guard GitHubService.shared.isAuthenticated else { throw SyncError.notAuthenticated }
        guard let data = try await GitHubService.shared.downloadIfExists(
            repository: repository,
            path: LibraryBackupManifest.path
        ) else {
            return nil
        }
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
        }
    }
}
