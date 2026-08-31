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
}
