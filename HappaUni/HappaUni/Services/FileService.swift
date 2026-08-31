import Foundation

struct ImportedLocalFile {
    let url: URL
    let type: DocumentType
    let size: Int64
    let modifiedAt: Date

    func makeDocument(folderID: UUID? = nil) -> LibraryDocument {
        LibraryDocument(
            name: url.lastPathComponent,
            url: url,
            type: type,
            size: size,
            modifiedAt: modifiedAt,
            folderID: folderID
        )
    }
}

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

    static let supportedTypes: Set<DocumentType> = [.pdf, .markdown, .tex, .epub, .text, .image]

    func importDocument(from sourceURL: URL) throws -> LibraryDocument {
        let importedFile = try importFiles([sourceURL], into: libraryDirectory())[0]
        return importedFile.makeDocument()
    }

    func importFiles(_ sourceURLs: [URL], into directory: URL) throws -> [ImportedLocalFile] {
        guard !sourceURLs.isEmpty else { return [] }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryDirectory = directory.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
        var committedURLs: [URL] = []

        do {
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
            var stagedFiles: [(url: URL, type: DocumentType)] = []

            for sourceURL in sourceURLs {
                let type = DocumentType.detect(from: sourceURL.lastPathComponent)
                guard Self.supportedTypes.contains(type) else { throw FileServiceError.unsupportedFile }

                let stagedURL = uniqueURL(in: temporaryDirectory, filename: sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: stagedURL)
                stagedFiles.append((url: stagedURL, type: type))
            }

            var importedFiles: [ImportedLocalFile] = []
            for stagedFile in stagedFiles {
                let destinationURL = uniqueURL(in: directory, filename: stagedFile.url.lastPathComponent)
                try fileManager.moveItem(at: stagedFile.url, to: destinationURL)
                committedURLs.append(destinationURL)

                let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                let modifiedAt = (attributes[.modificationDate] as? Date) ?? .now
                importedFiles.append(
                    ImportedLocalFile(
                        url: destinationURL,
                        type: stagedFile.type,
                        size: size,
                        modifiedAt: modifiedAt
                    )
                )
            }

            try fileManager.removeItem(at: temporaryDirectory)
            return importedFiles
        } catch {
            for url in committedURLs {
                try? fileManager.removeItem(at: url)
            }
            try? fileManager.removeItem(at: temporaryDirectory)
            throw error
        }
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
