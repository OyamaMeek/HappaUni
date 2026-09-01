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
            case .unsupportedFile: "请选择 PDF、Markdown、TeX、EPUB、文本或图片文件。"
            }
        }
    }

    static let supportedTypes: Set<DocumentType> = [.pdf, .markdown, .tex, .epub, .text, .image]

    func importDocument(from sourceURL: URL, preferredFilename: String? = nil) throws -> LibraryDocument {
        guard let preferredFilename else {
            let importedFile = try importFiles([sourceURL], into: documentsDirectory())[0]
            return importedFile.makeDocument()
        }

        let filename = URL(fileURLWithPath: preferredFilename).lastPathComponent
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let renamedSourceURL = stagingDirectory.appendingPathComponent(filename)
        defer { try? FileManager.default.removeItem(at: stagingDirectory) }

        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sourceURL, to: renamedSourceURL)
        let importedFile = try importFiles([renamedSourceURL], into: documentsDirectory())[0]
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
        let destination = uniqueURL(in: try documentsDirectory(), filename: filename)
        try data.write(to: destination, options: .atomic)
        let document = LibraryDocument(name: destination.lastPathComponent, url: destination, type: type, size: Int64(data.count))
        document.id = id
        document.isSyncedToGitHub = true
        document.gitCommitHash = gitSHA
        document.gitLastSyncAt = .now
        return document
    }

    func delete(_ document: LibraryDocument) throws {
        let fileManager = FileManager.default
        let documentsDirectory = try documentsDirectory()
        let fileName = URL(fileURLWithPath: document.path).lastPathComponent
        let legacyDirectory = documentsDirectory.appendingPathComponent("Library", isDirectory: true)
        let sharedLibraryDirectory = documentsDirectory.appendingPathComponent("资料库", isDirectory: true)

        let candidateURLs = uniqueURLs([
            document.url,
            URL(fileURLWithPath: document.path),
            documentsDirectory.appendingPathComponent(fileName),
            legacyDirectory.appendingPathComponent(fileName),
            sharedLibraryDirectory.appendingPathComponent(fileName)
        ])

        for url in candidateURLs where isInsideDocumentsDirectory(url, documentsDirectory: documentsDirectory) {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            try? PDFAnnotationStore.delete(for: url)
        }
    }

    func documentsDirectory() throws -> URL {
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw FileServiceError.documentsDirectoryUnavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Keeps the shared Documents container visible in the Files app even before
    /// the first user import. Imported documents remain directly under /Documents.
    func prepareSharedDocumentsDirectory() throws {
        let directory = try documentsDirectory()
        let libraryFolder = directory.appendingPathComponent("资料库", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
    }

    /// Moves files imported by earlier versions from Documents/Library to Documents.
    /// The returned mapping lets callers repair persisted absolute file paths.
    func migrateLegacyLibraryDirectory() throws -> [String: String] {
        let fileManager = FileManager.default
        let documents = try documentsDirectory()
        let legacyDirectory = documents.appendingPathComponent("Library", isDirectory: true)
        guard fileManager.fileExists(atPath: legacyDirectory.path) else { return [:] }

        var migratedPaths: [String: String] = [:]
        let contents = try fileManager.contentsOfDirectory(
            at: legacyDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        for sourceURL in contents {
            let values = try sourceURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }

            let destinationURL = uniqueURL(in: documents, filename: sourceURL.lastPathComponent)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            migratedPaths[sourceURL.path] = destinationURL.path
        }

        if (try? fileManager.contentsOfDirectory(atPath: legacyDirectory.path).isEmpty) == true {
            try? fileManager.removeItem(at: legacyDirectory)
        }
        return migratedPaths
    }

    func resolvedURL(for document: LibraryDocument) -> URL? {
        let fileManager = FileManager.default
        let resolvedURL = document.url
        guard fileManager.fileExists(atPath: resolvedURL.path) else { return nil }
        return resolvedURL
    }

    /// Compatibility alias for existing callers. It now returns Documents, not Documents/Library.
    func libraryDirectory() throws -> URL {
        try documentsDirectory()
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

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func isInsideDocumentsDirectory(_ url: URL, documentsDirectory: URL) -> Bool {
        let directoryPath = documentsDirectory.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        return urlPath.hasPrefix(directoryPath + "/")
    }
}
