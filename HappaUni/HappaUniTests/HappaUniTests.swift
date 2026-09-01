import Foundation
import Testing
@testable import HappaUni

struct HappaUniTests {
    @Test("EPUB package parser orders spine chapters")
    func ordersEPUBSpine() throws {
        let fixtureOPF = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>测试图书</dc:title>
          </metadata>
          <manifest>
            <item id="chapter-2" href="text/第二章.xhtml" media-type="application/xhtml+xml"/>
            <item id="chapter-1" href="text/第一章.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="chapter-1"/>
            <itemref idref="chapter-2"/>
          </spine>
        </package>
        """

        let book = try EPUBService.parsePackage(
            opf: fixtureOPF,
            baseURL: URL(fileURLWithPath: "/tmp/book")
        )

        #expect(book.title == "测试图书")
        #expect(book.chapters.map(\.title) == ["第一章", "第二章"])
        #expect(book.chapters.map(\.url.path) == [
            "/tmp/book/text/第一章.xhtml",
            "/tmp/book/text/第二章.xhtml"
        ])
    }

    @Test("LaTeX preview escapes document source")
    func escapesLaTeXPreview() {
        #expect(LaTeXService.html(for: #"x < y"#).contains("x &lt; y"))
    }

    @Test("EPUB reader unpacks a local stored archive into readable chapters")
    func opensStoredEPUBArchive() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let archiveURL = directory.appendingPathComponent("book.epub")
        try makeStoredZIP([
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", """
            <?xml version="1.0"?>
            <container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>
            """),
            ("OEBPS/content.opf", """
            <package><metadata><title>本地书</title></metadata><manifest>
            <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
            </manifest><spine><itemref idref="chapter"/></spine></package>
            """),
            ("OEBPS/chapter.xhtml", "<html><body><h1>第一章</h1></body></html>")
        ]).write(to: archiveURL)

        let book = try EPUBService.open(archiveURL)

        #expect(book.title == "本地书")
        #expect(book.chapters.map(\.title) == ["chapter"])
        #expect(FileManager.default.fileExists(atPath: book.chapters[0].url.path))
    }

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

    @Test("Documents are active until explicitly archived")
    func archivesDocument() {
        let document = LibraryDocument(
            name: "paper.pdf",
            url: URL(fileURLWithPath: "/tmp/paper.pdf"),
            size: 10
        )

        #expect(!document.isArchived)
        document.isArchived = true
        #expect(document.isArchived)
    }

    @Test("PDF annotation archives persist drawing data by document")
    func persistsPDFAnnotationArchive() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = URL(fileURLWithPath: "/tmp/annotated.pdf")
        let drawings = [0: Data([0x01, 0x02]), 4: Data([0x03])]

        try PDFAnnotationStore.save(drawings, for: documentURL, in: directory)

        #expect(PDFAnnotationStore.load(for: documentURL, in: directory) == drawings)
        #expect(
            PDFAnnotationStore.identifier(for: documentURL)
                != PDFAnnotationStore.identifier(for: URL(fileURLWithPath: "/tmp/other.pdf"))
        )
    }

    @Test("Importing a downloaded file can preserve its remote filename")
    func preservesPreferredImportedFilename() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try Data("PDF".utf8).write(to: sourceURL)

        let service = FileService()
        let document = try service.importDocument(
            from: sourceURL,
            preferredFilename: "GitHub 入门与实践.pdf"
        )

        #expect(document.name == "GitHub 入门与实践.pdf")
        #expect(FileManager.default.fileExists(atPath: document.url.path))
        try service.delete(document)
        #expect(!FileManager.default.fileExists(atPath: document.url.path))
    }

    @Test("Deleting a document removes a matching file left by an old container path")
    func deletesMigratedDocumentFile() throws {
        let service = FileService()
        let documentsDirectory = try service.documentsDirectory()
        let filename = "\(UUID().uuidString).pdf"
        let currentURL = documentsDirectory.appendingPathComponent(filename)
        try Data("PDF".utf8).write(to: currentURL)
        defer { try? FileManager.default.removeItem(at: currentURL) }

        let staleURL = URL(fileURLWithPath: "/private/var/old-container/Documents/\(filename)")
        let document = LibraryDocument(name: filename, url: staleURL, type: .pdf, size: 3)

        try service.delete(document)

        #expect(!FileManager.default.fileExists(atPath: currentURL.path))
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

    @Test("WebDAV response parser removes the server base path before listing files")
    func parsesWebDAVFilesFromServerBasePath() throws {
        let xml = """
        <D:multistatus xmlns:D="DAV:">
          <D:response><D:href>/dav/HappaUni/</D:href><D:propstat><D:prop><D:displayname>HappaUni</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
          <D:response><D:href>/dav/HappaUni/guide.pdf</D:href><D:propstat><D:prop><D:displayname>guide.pdf</D:displayname><D:getcontentlength>2048</D:getcontentlength><D:resourcetype/></D:prop></D:propstat></D:response>
        </D:multistatus>
        """

        let files = try WebDAVXMLParser().parse(
            data: Data(xml.utf8),
            basePath: "/HappaUni",
            serverBasePath: "/dav"
        )

        #expect(files.map(\.path) == ["/HappaUni/guide.pdf"])
    }

    @Test("AI context extractor keeps the newest content within its character limit")
    func truncatesAIContext() {
        let value = AIContextExtractor.truncate("abcdefghij", maximumCharacters: 6)
        #expect(value == "…efghij")
    }

    @Test("AI responses configure MathJax for inline and display LaTeX")
    func configuresAIResponseMathRenderer() {
        let html = AIMathRenderer.html(for: #"行内 \(x^2\)，块级 \[\begin{aligned}a&=b\end{aligned}\]"#)

        #expect(html.contains("tex-mml-chtml.js"))
        #expect(html.contains("inlineMath"))
        #expect(html.contains("displayMath"))
        #expect(html.contains("mathtools"))
        #expect(html.contains(#"\begin{aligned}"#))
    }

    @Test("Custom system prompt is combined with document context and math guidance")
    func combinesCustomSystemPrompt() {
        let prompt = AISettings.documentAssistantPrompt(
            customPrompt: "请简洁回答。",
            documentName: "数学笔记",
            documentContent: "泰勒展开"
        )

        #expect(prompt.contains("请简洁回答。"))
        #expect(prompt.contains("数学笔记"))
        #expect(prompt.contains("泰勒展开"))
        #expect(prompt.contains(#"\( ... \)"#))
    }

    @Test("Document outline extracts Markdown headings with matching anchors")
    func extractsMarkdownOutline() {
        let items = DocumentOutlineExtractor.markdownItems(source: "# 课程\n正文\n## 第一讲\n### 重点")

        #expect(items.map(\.title) == ["课程", "第一讲", "重点"])
        #expect(items.map(\.level) == [0, 1, 2])
        #expect(items.map(\.id) == ["heading-0", "heading-2", "heading-3"])
    }

    @Test("Knowledge map parser preserves nested AI outline")
    func parsesKnowledgeMap() {
        let map = KnowledgeMapParser.parse("计算机网络\n  - 分层模型\n    - 应用层\n  - 传输层", fallbackTitle: "PDF")

        #expect(map.title == "计算机网络")
        #expect(map.children.map(\.title) == ["分层模型", "传输层"])
        #expect(map.children.first?.children.map(\.title) == ["应用层"])
    }

    @Test("AI conversation messages retain their request role when restored")
    func restoresAIConversationMessageRole() {
        let message = AIConversationMessage(
            conversationID: UUID(),
            role: .user,
            content: "这份资料的重点是什么？"
        )

        #expect(message.asAIMessage().role == .user)
        #expect(message.asAIMessage().content == "这份资料的重点是什么？")
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
        #expect(WebDAVRemotePath.libraryRoot == "/HappaUni")
        #expect(WebDAVRemotePath.parent(of: "/HappaUni/course") == "/HappaUni")
    }

    @Test("GitHub sync paths recover a stable local document identifier")
    func parsesSyncedDocumentPath() throws {
        let id = UUID()
        let item = try SyncRemoteDocument(path: "documents/\(id.uuidString)/guide.pdf", sha: "abc123")

        #expect(item.documentID == id)
        #expect(item.filename == "guide.pdf")
        #expect(item.sha == "abc123")
    }

    @Test("Library metadata backup retains document and folder relationships")
    func retainsMetadataBackupRelationships() {
        let folder = LibraryFolder(name: "课程")
        let document = LibraryDocument(
            name: "guide.pdf",
            url: URL(fileURLWithPath: "/tmp/guide.pdf"),
            size: 10,
            isFavorite: true,
            tags: ["数学"],
            folderID: folder.id
        )
        let manifest = LibraryBackupManifest(documents: [document], folders: [folder])

        #expect(manifest.schemaVersion == 3)
        #expect(manifest.documents[0].folderID == folder.id)
        #expect(manifest.documents[0].tags == ["数学"])
        #expect(manifest.folders[0].name == "课程")
    }

    @Test("Trash documents use the dedicated GitHub backup folder")
    func usesTrashRemotePath() {
        let document = LibraryDocument(
            name: "paper.pdf",
            url: URL(fileURLWithPath: "/tmp/paper.pdf"),
            type: .pdf,
            size: 10,
            trashedAt: .now
        )

        #expect(document.isInTrash)
        #expect(LibraryRemotePath.documentPath(for: document, folders: []) == "废纸篓/paper.pdf")
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

    @Test("WebDAV cache isolates identical remote paths across accounts")
    func isolatesWebDAVAccountCaches() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = WebDAVCacheStore(directory: directory)
        let firstAccount = UUID()
        let secondAccount = UUID()

        let first = try cache.store(Data("first".utf8), accountID: firstAccount, remotePath: "/notes/guide.pdf")
        let second = try cache.store(Data("second".utf8), accountID: secondAccount, remotePath: "/notes/guide.pdf")

        #expect(first != second)
        #expect(cache.cachedURL(accountID: firstAccount, remotePath: "/notes/guide.pdf") == first)
        #expect(cache.cachedURL(accountID: secondAccount, remotePath: "/notes/guide.pdf") == second)
    }

    @Test("WebDAV upload queue deduplicates an unchanged pending upload")
    func deduplicatesQueuedWebDAVUploads() {
        let suiteName = "HappaUniTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let queue = WebDAVUploadQueue(defaults: defaults)
        let accountID = UUID()
        let localURL = URL(fileURLWithPath: "/tmp/guide.pdf")

        queue.enqueue(accountID: accountID, localURL: localURL, remotePath: "/notes/guide.pdf")
        queue.enqueue(accountID: accountID, localURL: localURL, remotePath: "/notes/guide.pdf")

        #expect(queue.items(for: accountID).count == 1)
    }

    @Test("WebDAV request URLs preserve server base path and absolute DAV hrefs")
    func resolvesWebDAVRequestURLs() {
        let serverURL = URL(string: "https://dav.example.com/root/dav/")!

        #expect(WebDAVRemotePath.url(serverURL: serverURL, path: "/notes/guide.pdf").absoluteString == "https://dav.example.com/root/dav/notes/guide.pdf")
        #expect(WebDAVRemotePath.requestURL(serverURL: serverURL, href: "/root/dav/notes/guide.pdf").absoluteString == "https://dav.example.com/root/dav/notes/guide.pdf")
        #expect(WebDAVRemotePath.requestURL(serverURL: serverURL, href: "/HappaUni/guide.pdf").absoluteString == "https://dav.example.com/root/dav/HappaUni/guide.pdf")
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

    @Test("Folder descendants terminate on a two-node parent cycle")
    func terminatesTwoNodeParentCycle() {
        let aID = UUID()
        let bID = UUID()
        let folderA = LibraryFolder(id: aID, name: "A", parentID: bID)
        let folderB = LibraryFolder(id: bID, name: "B", parentID: aID)

        #expect(FolderTreeBuilder.descendantIDs(of: aID, in: [folderA, folderB]) == [aID, bID])
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

    private func makeStoredZIP(_ entries: [(String, String)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for (path, content) in entries {
            let pathData = Data(path.utf8)
            let contentData = Data(content.utf8)
            let localOffset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x04034B50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt32(0))
            archive.appendLittleEndian(UInt32(contentData.count))
            archive.appendLittleEndian(UInt32(contentData.count))
            archive.appendLittleEndian(UInt16(pathData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(pathData)
            archive.append(contentData)

            centralDirectory.appendLittleEndian(UInt32(0x02014B50))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(UInt32(contentData.count))
            centralDirectory.appendLittleEndian(UInt32(contentData.count))
            centralDirectory.appendLittleEndian(UInt16(pathData.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(localOffset)
            centralDirectory.append(pathData)
        }

        let centralOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndian(UInt32(0x06054B50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(centralDirectory.count))
        archive.appendLittleEndian(centralOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        append(Data(bytes: &littleEndian, count: MemoryLayout<T>.size))
    }
}
