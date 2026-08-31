import Compression
import Foundation

struct EPUBChapter: Identifiable, Equatable {
    let title: String
    let url: URL

    var id: URL { url }
}

struct EPUBBook: Identifiable, Equatable {
    let url: URL
    let title: String
    let chapters: [EPUBChapter]
    let contentURL: URL

    var id: URL { url }
}

enum EPUBService {
    static func open(_ url: URL) throws -> EPUBBook {
        guard url.pathExtension.lowercased() == "epub" else { throw Error.invalidFile }

        let unpackedURL = try unpack(url)
        let containerURL = unpackedURL
            .appendingPathComponent("META-INF", isDirectory: true)
            .appendingPathComponent("container.xml")
        guard FileManager.default.fileExists(atPath: containerURL.path) else { throw Error.missingContainer }

        let packagePath = try EPUBContainerParser.packagePath(data: Data(contentsOf: containerURL))
        let packageURL = try localURL(for: packagePath, relativeTo: unpackedURL)
        guard FileManager.default.fileExists(atPath: packageURL.path) else { throw Error.missingPackage }

        let parsedBook = try parsePackage(
            opf: String(contentsOf: packageURL, encoding: .utf8),
            baseURL: packageURL.deletingLastPathComponent()
        )
        return EPUBBook(
            url: url,
            title: parsedBook.title,
            chapters: parsedBook.chapters,
            contentURL: unpackedURL
        )
    }

    static func parsePackage(opf: String, baseURL: URL) throws -> EPUBBook {
        let package = try EPUBPackageParser.parse(data: Data(opf.utf8))
        guard !package.manifest.isEmpty else { throw Error.invalidPackage }

        let chapters = try package.spine.compactMap { idref -> EPUBChapter? in
            guard let item = package.manifest[idref] else { return nil }
            guard item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html" else { return nil }
            let url = try localURL(for: item.href, relativeTo: baseURL)
            return EPUBChapter(title: chapterTitle(for: item.href), url: url)
        }
        guard !chapters.isEmpty else { throw Error.missingSpine }

        return EPUBBook(
            url: baseURL,
            title: package.title.isEmpty ? baseURL.lastPathComponent : package.title,
            chapters: chapters,
            contentURL: baseURL
        )
    }

    private static func unpack(_ url: URL) throws -> URL {
        let cacheRoot = try cacheRootURL()
        let destination = cacheRoot.appendingPathComponent(cacheDirectoryName(for: url), isDirectory: true)
        try removeStaleDirectories(in: cacheRoot, keeping: destination)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try EPUBZIPExtractor.extract(Data(contentsOf: url), to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw Error.cannotUnpack
        }
    }

    private static func cacheRootURL() throws -> URL {
        guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw Error.cannotCreateCache
        }
        let root = cacheDirectory.appendingPathComponent("EPUB", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func removeStaleDirectories(in root: URL, keeping destination: URL) throws {
        let directories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories where directory != destination {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try FileManager.default.removeItem(at: directory)
            }
        }
    }

    private static func cacheDirectoryName(for url: URL) -> String {
        let stableHash = url.path.utf8.reduce(UInt64(1_469_598_103_934_665_603)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(format: "%016llx", stableHash)
    }

    private static func localURL(for path: String, relativeTo baseURL: URL) throws -> URL {
        let decodedPath = path.removingPercentEncoding ?? path
        guard !decodedPath.hasPrefix("/"), !decodedPath.split(separator: "/").contains("..") else {
            throw Error.invalidPackage
        }
        let resolved = baseURL.appendingPathComponent(decodedPath).standardizedFileURL
        let rootPath = baseURL.standardizedFileURL.path
        guard resolved.path == rootPath || resolved.path.hasPrefix(rootPath + "/") else { throw Error.invalidPackage }
        return resolved
    }

    private static func chapterTitle(for href: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        return URL(fileURLWithPath: decoded).deletingPathExtension().lastPathComponent
    }

    enum Error: LocalizedError {
        case invalidFile
        case cannotCreateCache
        case cannotUnpack
        case missingContainer
        case missingPackage
        case invalidPackage
        case missingSpine

        var errorDescription: String? {
            switch self {
            case .invalidFile: "请选择 EPUB 文件。"
            case .cannotCreateCache: "无法创建 EPUB 阅读缓存。"
            case .cannotUnpack: "无法解压 EPUB 文件，无法显示完整阅读内容。"
            case .missingContainer: "EPUB 缺少 META-INF/container.xml，无法显示完整阅读内容。"
            case .missingPackage: "EPUB 书籍包不存在，无法显示完整阅读内容。"
            case .invalidPackage: "EPUB 书籍包格式无效，无法显示完整阅读内容。"
            case .missingSpine: "EPUB 未包含可阅读章节，无法显示完整阅读内容。"
            }
        }
    }
}

private final class EPUBContainerParser: NSObject, XMLParserDelegate {
    private var packagePath: String?

    static func packagePath(data: Data) throws -> String {
        let delegate = EPUBContainerParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let packagePath = delegate.packagePath, !packagePath.isEmpty else {
            throw EPUBService.Error.invalidPackage
        }
        return packagePath
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.localName == "rootfile" else { return }
        packagePath = attributeDict["full-path"]
    }
}

private final class EPUBPackageParser: NSObject, XMLParserDelegate {
    struct ManifestItem {
        let href: String
        let mediaType: String
    }

    private(set) var title = ""
    private(set) var manifest: [String: ManifestItem] = [:]
    private(set) var spine: [String] = []
    private var currentElement = ""

    static func parse(data: Data) throws -> EPUBPackageParser {
        let delegate = EPUBPackageParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? EPUBService.Error.invalidPackage }
        return delegate
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName.localName
        switch currentElement {
        case "item":
            guard let id = attributeDict["id"], let href = attributeDict["href"] else { return }
            manifest[id] = ManifestItem(href: href, mediaType: attributeDict["media-type"] ?? "")
        case "itemref":
            if let idref = attributeDict["idref"] { spine.append(idref) }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentElement == "title" else { return }
        title += string
    }
}

private extension String {
    var localName: String {
        split(separator: ":").last.map(String.init) ?? self
    }
}

private enum EPUBZIPExtractor {
    private static let localHeaderSignature: UInt32 = 0x04034B50
    private static let centralDirectorySignature: UInt32 = 0x02014B50
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054B50
    private static let maximumArchiveSize = 200 * 1_024 * 1_024
    private static let maximumEntryCount = 4_096
    private static let maximumUncompressedSize = 250 * 1_024 * 1_024

    static func extract(_ archive: Data, to destination: URL) throws {
        guard archive.count <= maximumArchiveSize else { throw EPUBService.Error.cannotUnpack }
        let directory = try centralDirectory(in: archive)
        guard directory.entryCount <= maximumEntryCount else { throw EPUBService.Error.cannotUnpack }

        var cursor = directory.offset
        let end = directory.offset + directory.size
        var totalUncompressedSize = 0

        for _ in 0..<directory.entryCount {
            let signature = try archive.uint32(at: cursor)
            guard cursor + 46 <= end, signature == centralDirectorySignature else {
                throw EPUBService.Error.cannotUnpack
            }

            let flags = try archive.uint16(at: cursor + 8)
            let compressionMethod = try archive.uint16(at: cursor + 10)
            let compressedSize = try archive.uint32(at: cursor + 20)
            let uncompressedSize = try archive.uint32(at: cursor + 24)
            let filenameLength = try archive.uint16(at: cursor + 28)
            let extraLength = try archive.uint16(at: cursor + 30)
            let commentLength = try archive.uint16(at: cursor + 32)
            let localHeaderOffset = try archive.uint32(at: cursor + 42)
            let headerSize = 46 + Int(filenameLength) + Int(extraLength) + Int(commentLength)

            guard cursor + headerSize <= end, flags & 0x0001 == 0 else {
                throw EPUBService.Error.cannotUnpack
            }
            let filenameRange = (cursor + 46)..<(cursor + 46 + Int(filenameLength))
            let relativePath = try safeRelativePath(from: archive[filenameRange])

            guard totalUncompressedSize <= maximumUncompressedSize - Int(uncompressedSize) else {
                throw EPUBService.Error.cannotUnpack
            }
            totalUncompressedSize += Int(uncompressedSize)
            guard totalUncompressedSize <= maximumUncompressedSize else { throw EPUBService.Error.cannotUnpack }

            if relativePath.hasSuffix("/") {
                try FileManager.default.createDirectory(
                    at: destination.appendingPathComponent(relativePath, isDirectory: true),
                    withIntermediateDirectories: true
                )
            } else {
                let contents = try entryContents(
                    archive,
                    localHeaderOffset: Int(localHeaderOffset),
                    compressedSize: Int(compressedSize),
                    uncompressedSize: Int(uncompressedSize),
                    compressionMethod: compressionMethod
                )
                let outputURL = destination.appendingPathComponent(relativePath)
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try contents.write(to: outputURL, options: .atomic)
            }

            cursor += headerSize
        }

        guard cursor == end else { throw EPUBService.Error.cannotUnpack }
    }

    private static func centralDirectory(in archive: Data) throws -> (offset: Int, size: Int, entryCount: Int) {
        let minimumSize = 22
        guard archive.count >= minimumSize else { throw EPUBService.Error.cannotUnpack }
        let lowerBound = max(0, archive.count - minimumSize - Int(UInt16.max))
        let upperBound = archive.count - minimumSize

        guard let offset = stride(from: upperBound, through: lowerBound, by: -1).first(where: {
            archive.optionalUInt32(at: $0) == endOfCentralDirectorySignature
        }) else {
            throw EPUBService.Error.cannotUnpack
        }

        let currentDisk = try archive.uint16(at: offset + 4)
        let directoryDisk = try archive.uint16(at: offset + 6)
        let entriesOnDisk = try archive.uint16(at: offset + 8)
        let entryCount = try archive.uint16(at: offset + 10)
        let size = try archive.uint32(at: offset + 12)
        let directoryOffset = try archive.uint32(at: offset + 16)
        guard currentDisk == 0, directoryDisk == 0, entriesOnDisk == entryCount else {
            throw EPUBService.Error.cannotUnpack
        }

        let directoryStart = Int(directoryOffset)
        let directorySize = Int(size)
        guard directoryStart >= 0, directorySize >= 0, directoryStart + directorySize <= archive.count else {
            throw EPUBService.Error.cannotUnpack
        }
        return (directoryStart, directorySize, Int(entryCount))
    }

    private static func safeRelativePath(from filename: Data.SubSequence) throws -> String {
        guard let path = String(data: Data(filename), encoding: .utf8),
              !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\")
        else {
            throw EPUBService.Error.cannotUnpack
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let pathIsDirectory = path.hasSuffix("/")
        guard components.enumerated().allSatisfy({ index, component in
            pathIsDirectory && index == components.count - 1 && component.isEmpty
                || (!component.isEmpty && component != "." && component != "..")
        }) else {
            throw EPUBService.Error.cannotUnpack
        }
        return path
    }

    private static func entryContents(
        _ archive: Data,
        localHeaderOffset: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        compressionMethod: UInt16
    ) throws -> Data {
        guard localHeaderOffset >= 0,
              localHeaderOffset + 30 <= archive.count,
              try archive.uint32(at: localHeaderOffset) == localHeaderSignature
        else {
            throw EPUBService.Error.cannotUnpack
        }
        let filenameLength = try archive.uint16(at: localHeaderOffset + 26)
        let extraLength = try archive.uint16(at: localHeaderOffset + 28)
        let contentStart = localHeaderOffset + 30 + Int(filenameLength) + Int(extraLength)
        let contentEnd = contentStart + compressedSize
        guard contentStart >= 0, contentEnd <= archive.count else { throw EPUBService.Error.cannotUnpack }

        let compressed = archive[contentStart..<contentEnd]
        switch compressionMethod {
        case 0:
            guard compressed.count == uncompressedSize else { throw EPUBService.Error.cannotUnpack }
            return Data(compressed)
        case 8:
            return try inflate(Data(compressed), expectedSize: uncompressedSize)
        default:
            throw EPUBService.Error.cannotUnpack
        }
    }

    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize <= maximumUncompressedSize else { throw EPUBService.Error.cannotUnpack }
        guard expectedSize > 0 else { return Data() }
        guard !compressed.isEmpty else { throw EPUBService.Error.cannotUnpack }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { outputBuffer in
            compressed.withUnsafeBytes { compressedBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    expectedSize,
                    compressedBuffer.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw EPUBService.Error.cannotUnpack }
        return output
    }
}

private extension Data {
    func uint16(at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { throw EPUBService.Error.cannotUnpack }
        let first = UInt16(self[startIndex + offset])
        let second = UInt16(self[startIndex + offset + 1])
        return first | (second << 8)
    }

    func optionalUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        let first = UInt32(self[startIndex + offset])
        let second = UInt32(self[startIndex + offset + 1])
        let third = UInt32(self[startIndex + offset + 2])
        let fourth = UInt32(self[startIndex + offset + 3])
        return first | (second << 8) | (third << 16) | (fourth << 24)
    }

    func uint32(at offset: Int) throws -> UInt32 {
        guard let value = optionalUInt32(at: offset) else { throw EPUBService.Error.cannotUnpack }
        return value
    }
}
