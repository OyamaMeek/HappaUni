import Foundation

struct PendingWebDAVUpload: Codable, Identifiable, Equatable {
    let id: UUID
    let accountID: UUID
    let localPath: String
    let remotePath: String
    let createdAt: Date
    var attemptCount: Int

    init(
        id: UUID = UUID(),
        accountID: UUID,
        localURL: URL,
        remotePath: String,
        createdAt: Date = .now,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.accountID = accountID
        self.localPath = localURL.path
        self.remotePath = remotePath
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }

    var localURL: URL { URL(fileURLWithPath: localPath) }
}

final class WebDAVUploadQueue {
    static let shared = WebDAVUploadQueue()

    private let defaults: UserDefaults
    private let storageKey = "webdav.pendingUploads"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func items(for accountID: UUID) -> [PendingWebDAVUpload] {
        items().filter { $0.accountID == accountID }
    }

    func enqueue(accountID: UUID, localURL: URL, remotePath: String) {
        var values = items()
        guard !values.contains(where: {
            $0.accountID == accountID && $0.localPath == localURL.path && $0.remotePath == remotePath
        }) else {
            return
        }
        values.append(PendingWebDAVUpload(accountID: accountID, localURL: localURL, remotePath: remotePath))
        save(values)
    }

    func remove(_ id: UUID) {
        save(items().filter { $0.id != id })
    }

    func markAttempt(_ id: UUID) {
        var values = items()
        guard let index = values.firstIndex(where: { $0.id == id }) else { return }
        values[index].attemptCount += 1
        save(values)
    }

    private func items() -> [PendingWebDAVUpload] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWebDAVUpload].self, from: data)) ?? []
    }

    private func save(_ values: [PendingWebDAVUpload]) {
        defaults.set(try? JSONEncoder().encode(values), forKey: storageKey)
    }
}
