import CryptoKit
import Foundation

struct WebDAVCacheStore {
    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.directory = caches.appendingPathComponent("HappaUni/WebDAV", isDirectory: true)
        }
    }

    func store(_ data: Data, forRemotePath path: String) throws -> URL {
        try store(data, cacheKey: path, pathExtensionSource: path)
    }

    func store(_ data: Data, accountID: UUID, remotePath: String) throws -> URL {
        try store(
            data,
            cacheKey: "\(accountID.uuidString)\n\(remotePath)",
            pathExtensionSource: remotePath
        )
    }

    func cachedURL(accountID: UUID, remotePath: String) -> URL? {
        let url = fileURL(
            cacheKey: "\(accountID.uuidString)\n\(remotePath)",
            pathExtensionSource: remotePath
        )
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func store(_ data: Data, cacheKey: String, pathExtensionSource: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(cacheKey: cacheKey, pathExtensionSource: pathExtensionSource)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func fileURL(cacheKey: String, pathExtensionSource: String) -> URL {
        let digest = SHA256.hash(data: Data(cacheKey.utf8)).compactMap { String(format: "%02x", $0) }.joined()
        let ext = (pathExtensionSource as NSString).pathExtension
        let filename = ext.isEmpty ? digest : "\(digest).\(ext)"
        return directory.appendingPathComponent(filename)
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    func size() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return enumerator.compactMap { $0 as? URL }.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }
}
