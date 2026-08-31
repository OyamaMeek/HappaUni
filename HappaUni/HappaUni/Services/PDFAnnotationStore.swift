import CryptoKit
import Foundation

struct PDFAnnotationArchive: Codable {
    var drawings: [Int: Data]
}

enum PDFAnnotationStore {
    static func load(for documentURL: URL, in directory: URL? = nil) -> [Int: Data] {
        let fileURL = archiveURL(for: documentURL, in: directory)
        guard
            let data = try? Data(contentsOf: fileURL),
            let archive = try? JSONDecoder().decode(PDFAnnotationArchive.self, from: data)
        else {
            return [:]
        }
        return archive.drawings
    }

    static func save(
        _ drawings: [Int: Data],
        for documentURL: URL,
        in directory: URL? = nil
    ) throws {
        let targetDirectory = try resolvedDirectory(directory)
        let fileURL = targetDirectory.appendingPathComponent(identifier(for: documentURL))
        let data = try JSONEncoder().encode(PDFAnnotationArchive(drawings: drawings))
        try data.write(to: fileURL, options: .atomic)
    }

    static func identifier(for documentURL: URL) -> String {
        let path = documentURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".annotations"
    }

    private static func archiveURL(for documentURL: URL, in directory: URL?) -> URL {
        let directory = (try? resolvedDirectory(directory)) ?? documentURL.deletingLastPathComponent()
        return directory.appendingPathComponent(identifier(for: documentURL))
    }

    private static func resolvedDirectory(_ directory: URL?) throws -> URL {
        let directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HappaUni/PDFAnnotations", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
