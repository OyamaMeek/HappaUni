import Foundation

struct FileService {
    enum FileServiceError: LocalizedError {
        case documentsDirectoryUnavailable
        case unsupportedFile

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable: "无法访问本地资料库目录。"
            case .unsupportedFile: "请选择 PDF、Markdown、EPUB、文本或图片文件。"
            }
        }
    }

    static let supportedTypes: Set<DocumentType> = [.pdf, .markdown, .epub, .text, .image]

    func importDocument(from sourceURL: URL) throws -> LibraryDocument {
        let type = DocumentType.detect(from: sourceURL.lastPathComponent)
        guard Self.supportedTypes.contains(type) else { throw FileServiceError.unsupportedFile }

        let directory = try libraryDirectory()
        let destination = uniqueURL(in: directory, filename: sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date) ?? .now

        return LibraryDocument(
            name: destination.lastPathComponent,
            url: destination,
            type: type,
            size: size,
            modifiedAt: modifiedAt
        )
    }

    func restoreDocument(data: Data, filename: String, id: UUID, gitSHA: String) throws -> LibraryDocument {
        let type = DocumentType.detect(from: filename)
        guard Self.supportedTypes.contains(type) else { throw FileServiceError.unsupportedFile }
        let destination = uniqueURL(in: try libraryDirectory(), filename: filename)
        try data.write(to: destination, options: .atomic)
        let document = LibraryDocument(name: destination.lastPathComponent, url: destination, type: type, size: Int64(data.count))
        document.id = id
        document.isSyncedToGitHub = true
        document.gitCommitHash = gitSHA
        document.gitLastSyncAt = .now
        return document
    }

    func delete(_ document: LibraryDocument) throws {
        guard FileManager.default.fileExists(atPath: document.path) else { return }
        try FileManager.default.removeItem(at: document.url)
    }

    func libraryDirectory() throws -> URL {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw FileServiceError.documentsDirectoryUnavailable
        }
        let library = directory.appendingPathComponent("Library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        return library
    }

    private func uniqueURL(in directory: URL, filename: String) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            candidate = directory.appendingPathComponent("\(base) (\(index))\(suffix)")
            index += 1
        }
        return candidate
    }
}
