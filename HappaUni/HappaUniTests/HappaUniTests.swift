import Foundation
import Testing
@testable import HappaUni

struct HappaUniTests {
    @Test("DocumentType detects supported file extensions")
    func detectsDocumentTypes() {
        #expect(DocumentType.detect(from: "research.PDF") == .pdf)
        #expect(DocumentType.detect(from: "notes.markdown") == .markdown)
        #expect(DocumentType.detect(from: "book.epub") == .epub)
        #expect(DocumentType.detect(from: "archive.zip") == .other)
    }

    @Test("Document type detects TeX source")
    func detectsTeX() {
        #expect(DocumentType.detect(from: "report.tex") == .tex)
    }

    @Test("Document records expose a readable file size")
    func formatsFileSize() {
        let document = LibraryDocument(
            name: "paper.pdf",
            url: URL(fileURLWithPath: "/tmp/paper.pdf"),
            type: .pdf,
            size: 1_536
        )
        #expect(document.formattedSize == "1.5 KB")
    }

    @Test("WebDAV response parser excludes the requested directory")
    func parsesWebDAVFiles() throws {
        let xml = """
        <D:multistatus xmlns:D="DAV:">
          <D:response><D:href>/docs/</D:href><D:propstat><D:prop><D:displayname>docs</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/docs/guide.pdf</D:href><D:propstat><D:prop><D:displayname>guide.pdf</D:displayname><D:getcontentlength>2048</D:getcontentlength><D:getetag>\"abc\"</D:getetag><D:resourcetype/></D:prop></D:propstat></D:response>
        </D:multistatus>
        """
        let files = try WebDAVXMLParser().parse(data: Data(xml.utf8), basePath: "/docs/")
        #expect(files.count == 1)
        #expect(files[0].name == "guide.pdf")
        #expect(files[0].size == 2_048)
        #expect(!files[0].isDirectory)
    }

    @Test("AI context extractor keeps the newest content within its character limit")
    func truncatesAIContext() {
        let value = AIContextExtractor.truncate("abcdefghij", maximumCharacters: 6)
        #expect(value == "…efghij")
    }

    @Test("WebDAV account input normalizes a server URL and requires credentials")
    func validatesWebDAVAccountInput() throws {
        let input = WebDAVAccountInput(
            name: "坚果云",
            serverAddress: "dav.jianguoyun.com/dav/",
            username: "reader@example.com",
            password: "secret"
        )

        #expect(try input.validatedURL().absoluteString == "https://dav.jianguoyun.com/dav/")
        #expect(try input.validatedName() == "坚果云")
    }

    @Test("WebDAV paths preserve nested folders without duplicate slashes")
    func joinsWebDAVPaths() {
        #expect(WebDAVRemotePath.join(base: "/notes/", child: "2026/guide.pdf") == "/notes/2026/guide.pdf")
        #expect(WebDAVRemotePath.join(base: "/", child: "/guide.pdf") == "/guide.pdf")
    }

    @Test("GitHub sync paths recover a stable local document identifier")
    func parsesSyncedDocumentPath() throws {
        let id = UUID()
        let item = try SyncRemoteDocument(path: "documents/\(id.uuidString)/guide.pdf", sha: "abc123")

        #expect(item.documentID == id)
        #expect(item.filename == "guide.pdf")
        #expect(item.sha == "abc123")
    }

    @Test("WebDAV cache keeps distinct remote files with the same filename")
    func cachesDistinctRemoteFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WebDAVCacheStore(directory: directory)

        let first = try cache.store(Data("first".utf8), forRemotePath: "/courses/a/notes.pdf")
        let second = try cache.store(Data("second".utf8), forRemotePath: "/courses/b/notes.pdf")

        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("first".utf8))
        #expect(try Data(contentsOf: second) == Data("second".utf8))
    }

    @Test("Document tags normalize whitespace and duplicates")
    func normalizesDocumentTags() {
        let document = LibraryDocument(name: "paper.pdf", url: URL(fileURLWithPath: "/tmp/paper.pdf"), size: 1)
        document.tags = ["  课程 ", "论文", "课程", ""]

        #expect(document.tags == ["课程", "论文"])
    }

    @Test("Folder tree attaches nested folders to their parent")
    func buildsFolderTree() {
        let root = LibraryFolder(name: "课程")
        let child = LibraryFolder(name: "数学", parentID: root.id)
        let nodes = FolderTreeBuilder.make(from: [child, root])

        #expect(nodes.count == 1)
        #expect(nodes[0].folder.id == root.id)
        #expect(nodes[0].children.map(\.folder.id) == [child.id])
    }

    @Test("Folder descendants include nested folders and exclude cycles")
    func findsFolderDescendants() {
        let root = LibraryFolder(name: "课程")
        let child = LibraryFolder(name: "数学", parentID: root.id)
        let grandchild = LibraryFolder(name: "高数", parentID: child.id)

        #expect(FolderTreeBuilder.descendantIDs(of: root.id, in: [root, child, grandchild]) == [root.id, child.id, grandchild.id])
    }

    @Test("Atomic local imports remove copied files after a later copy fails")
    func rollsBackPartialImport() throws {
        let sourceDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destinationDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: sourceDirectory)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }

        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let validSource = sourceDirectory.appendingPathComponent("first.txt")
        let missingSource = sourceDirectory.appendingPathComponent("missing.txt")
        try Data("first".utf8).write(to: validSource)

        #expect(throws: Error.self) {
            try FileService().importFiles([validSource, missingSource], into: destinationDirectory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destinationDirectory.path).isEmpty)
    }
}
