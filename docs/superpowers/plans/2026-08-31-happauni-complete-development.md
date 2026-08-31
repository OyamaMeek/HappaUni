# HappaUni Complete Development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the remaining HappaUni document-library, synchronization, AI, settings, and LaTeX capabilities for iPadOS 17+ while retaining the existing bottom floating action capsule and current dark native interface.

**Architecture:** Keep SwiftData as the local source of truth and split services by protocol/storage concern. Add small SwiftUI reader/settings views that route through existing `ContentView` and `DocumentReaderView`; service code stays deterministic and covered with `Testing` tests before UI integration.

**Tech Stack:** Swift 5.9, SwiftUI, SwiftData, PDFKit, WebKit, Foundation URLSession/XMLParser, Testing, iOS 17.

## Global Constraints

- Swift 5.9, SwiftUI, SwiftData, deployment target iOS 17.0.
- Do not introduce a global liquid-glass theme; retain current dark native interface and existing bottom floating action capsule.
- API keys, tokens, and passwords stay in `KeychainStore`; never persist secrets in SwiftData, UserDefaults, source control, or logs.
- WebDAV cache identity includes the account UUID and complete remote path.
- GitHub recovery never overwrites a newer local file; preserve a recoverable conflict copy.
- Each behavior begins with a failing `Testing` test, followed by focused green verification and a full `xcodebuild test` before commit.
- Stage only files changed by the current task; do not stage `HappaUni/HappaUni.xcodeproj/project.xcworkspace/xcuserdata/oyamahappa.xcuserdatad/UserInterfaceState.xcuserstate` or `HANDOFF/`.

---

## File Structure

- `Models/LibraryDocument.swift`: supported document types and persisted reader/sync metadata.
- `Models/LibraryFolder.swift`: cycle-safe folder tree and descendant lookup.
- `Models/AIChatSession.swift`: persisted chat sessions and messages.
- `Services/FileService.swift`: transactional local import and recoverable file paths.
- `Services/PDFService.swift`, `Services/EPUBService.swift`, `Services/LaTeXService.swift`: format-specific parsing and rendering models.
- `Services/WebDAVCacheStore.swift`, `Services/WebDAVUploadQueue.swift`, `Services/WebDAVService.swift`: cached remote storage, retry queue, DAV protocol mutations.
- `Services/GitHubService.swift`, `Services/SyncService.swift`: remote repository API, metadata manifest, restore/conflicts.
- `Services/AIService.swift`: document extraction, OpenAI-compatible streaming and response usage.
- `Views/*ReaderView.swift`, `Views/LaTeXEditorView.swift`, `Views/*SettingsView.swift`: focused UI layers.
- `HappaUniTests/HappaUniTests.swift`: deterministic service/model regression coverage.

### Task 1: Local Library Integrity and Reader Routing

**Files:**
- Modify: `HappaUni/HappaUni/Models/LibraryDocument.swift`
- Modify: `HappaUni/HappaUni/Models/LibraryFolder.swift`
- Modify: `HappaUni/HappaUni/Services/FileService.swift`
- Modify: `HappaUni/HappaUni/ContentView.swift`
- Modify: `HappaUni/HappaUni/Views/DocumentReaderView.swift`
- Create: `HappaUni/HappaUni/Views/MetadataEditorView.swift`
- Test: `HappaUni/HappaUniTests/HappaUniTests.swift`

**Interfaces:**
- Produces `DocumentType.tex`, `FolderTreeBuilder.descendantIDs(of:in:) -> Set<UUID>`, and `FileService.importFiles(_:into:) throws -> [ImportedLocalFile]` with all-or-nothing file rollback.

- [ ] **Step 1: Write failing tests**

```swift
@Test("Folder descendants include nested folders and exclude cycles")
func findsFolderDescendants() {
    let root = LibraryFolder(name: "课程")
    let child = LibraryFolder(name: "数学", parentID: root.id)
    let grandchild = LibraryFolder(name: "高数", parentID: child.id)
    #expect(FolderTreeBuilder.descendantIDs(of: root.id, in: [root, child, grandchild]) == [root.id, child.id, grandchild.id])
}

@Test("Document type detects TeX source")
func detectsTeX() {
    #expect(DocumentType.detect(from: "report.tex") == .tex)
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project HappaUni/HappaUni.xcodeproj -scheme HappaUni -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -only-testing:HappaUniTests/HappaUniTests/detectsTeX -only-testing:HappaUniTests/HappaUniTests/findsFolderDescendants`

Expected: the missing enum case and descendant method make the tests fail.

- [ ] **Step 3: Implement the smallest model/service changes**

```swift
static func descendantIDs(of rootID: UUID, in folders: [LibraryFolder]) -> Set<UUID> {
    let children = Dictionary(grouping: folders, by: \ .parentID)
    var visited: Set<UUID> = []
    func visit(_ id: UUID) {
        guard visited.insert(id).inserted else { return }
        for child in children[id] ?? [] { visit(child.id) }
    }
    visit(rootID)
    return visited
}
```

Use a temporary import directory and remove every copied URL if any source copy fails. Add metadata editing for name, tags, and folder assignment. Make parent-folder filtering include all descendant IDs.

- [ ] **Step 4: Run focused tests and full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project HappaUni/HappaUni.xcodeproj -scheme HappaUni -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add HappaUni/HappaUni/Models/LibraryDocument.swift HappaUni/HappaUni/Models/LibraryFolder.swift HappaUni/HappaUni/Services/FileService.swift HappaUni/HappaUni/ContentView.swift HappaUni/HappaUni/Views/DocumentReaderView.swift HappaUni/HappaUni/Views/MetadataEditorView.swift HappaUni/HappaUniTests/HappaUniTests.swift
git commit -m "feat: complete local library management"
git push
```

### Task 2: PDF, Markdown, EPUB, and LaTeX Readers

**Files:**
- Create: `HappaUni/HappaUni/Services/PDFService.swift`
- Modify: `HappaUni/HappaUni/Services/EPUBService.swift`
- Create: `HappaUni/HappaUni/Services/LaTeXService.swift`
- Create: `HappaUni/HappaUni/Views/PDFReaderView.swift`
- Create: `HappaUni/HappaUni/Views/MarkdownReaderView.swift`
- Create: `HappaUni/HappaUni/Views/EPUBReaderView.swift`
- Create: `HappaUni/HappaUni/Views/LaTeXEditorView.swift`
- Modify: `HappaUni/HappaUni/Views/DocumentReaderView.swift`
- Test: `HappaUni/HappaUniTests/HappaUniTests.swift`

**Interfaces:**
- Produces `PDFDocumentState`, `EPUBBook`, `EPUBChapter`, `EPUBService.parsePackage(...) throws -> EPUBBook`, and `LaTeXService.html(for:) -> String`.

- [ ] **Step 1: Write failing parser tests**

```swift
@Test("EPUB package parser orders spine chapters")
func ordersEPUBSpine() throws {
    let book = try EPUBService.parsePackage(opf: fixtureOPF, baseURL: URL(fileURLWithPath: "/tmp/book"))
    #expect(book.chapters.map(\.title) == ["第一章", "第二章"])
}

@Test("LaTeX preview escapes document source")
func escapesLaTeXPreview() {
    #expect(LaTeXService.html(for: #"x < y"#).contains("x &lt; y"))
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run the two named tests with `xcodebuild test -only-testing:` against the iPad Pro 11-inch (M5) simulator.

Expected: the missing parser and renderer symbols fail compilation.

- [ ] **Step 3: Implement readers**

Use `PDFView` coordination for page count, page navigation, search and zoom. Use `WKWebView` for Markdown dark CSS and EPUB XHTML chapter rendering. EPUB parsing must safely unpack into an app-cache directory, read `META-INF/container.xml`, parse OPF manifest/spine, resolve local chapter URLs, and remove stale unpacked directories. Implement a TeX source editor that saves UTF-8 and previews escaped source in an isolated HTML document.

- [ ] **Step 4: Run focused tests and full suite**

Run: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project HappaUni/HappaUni.xcodeproj -scheme HappaUni -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'`

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add HappaUni/HappaUni/Services/PDFService.swift HappaUni/HappaUni/Services/EPUBService.swift HappaUni/HappaUni/Services/LaTeXService.swift HappaUni/HappaUni/Views/PDFReaderView.swift HappaUni/HappaUni/Views/MarkdownReaderView.swift HappaUni/HappaUni/Views/EPUBReaderView.swift HappaUni/HappaUni/Views/LaTeXEditorView.swift HappaUni/HappaUni/Views/DocumentReaderView.swift HappaUni/HappaUniTests/HappaUniTests.swift
git commit -m "feat: add format-specific document readers"
git push
```

### Task 3: WebDAV Cache, Queue, and Remote File Operations

**Files:**
- Modify: `HappaUni/HappaUni/Services/WebDAVCacheStore.swift`
- Modify: `HappaUni/HappaUni/Services/WebDAVService.swift`
- Create: `HappaUni/HappaUni/Services/WebDAVUploadQueue.swift`
- Modify: `HappaUni/HappaUni/Views/WebDAVBrowserView.swift`
- Test: `HappaUni/HappaUniTests/HappaUniTests.swift`

**Interfaces:**
- Produces `WebDAVCacheStore.store(_:accountID:remotePath:)`, `cachedURL(accountID:remotePath:)`, `WebDAVService.makeDirectory`, `delete`, and `WebDAVUploadQueue.enqueue(_:)/retryPending()`.

- [ ] **Step 1: Write failing tests**

```swift
@Test("WebDAV cache separates identical paths between accounts")
func separatesWebDAVAccounts() throws {
    let cache = WebDAVCacheStore(directory: temporaryDirectory)
    let first = try cache.store(Data("one".utf8), accountID: UUID(), remotePath: "/notes/a.pdf")
    let second = try cache.store(Data("two".utf8), accountID: UUID(), remotePath: "/notes/a.pdf")
    #expect(first != second)
}

@Test("DAV URL resolver does not duplicate server base path")
func resolvesDAVHref() {
    #expect(WebDAVRemotePath.requestURL(serverURL: URL(string: "https://host/dav/")!, href: "/dav/a.pdf").path == "/dav/a.pdf")
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run the two named tests with `xcodebuild test -only-testing:`.

Expected: missing cache identity and URL resolver fail.

- [ ] **Step 3: Implement smallest reliable WebDAV changes**

Add HTTPS validation, correct absolute DAV `href` resolution, cache account IDs, MKCOL and DELETE request methods, `If-Match` headers for upload, and typed HTTP errors including precondition conflict. Queue only durable local file URLs and remote paths; retry retryable network/5xx errors with delays of 1, 2, and 4 seconds; surface conflict without overwrite.

- [ ] **Step 4: Run focused tests and full suite**

Run the full iPad destination `xcodebuild test` command.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add HappaUni/HappaUni/Services/WebDAVCacheStore.swift HappaUni/HappaUni/Services/WebDAVService.swift HappaUni/HappaUni/Services/WebDAVUploadQueue.swift HappaUni/HappaUni/Views/WebDAVBrowserView.swift HappaUni/HappaUniTests/HappaUniTests.swift
git commit -m "feat: harden webdav synchronization"
git push
```

### Task 4: GitHub Metadata Backup and Safe Recovery

**Files:**
- Modify: `HappaUni/HappaUni/Services/GitHubService.swift`
- Modify: `HappaUni/HappaUni/Services/SyncService.swift`
- Modify: `HappaUni/HappaUni/Views/SettingsView.swift`
- Test: `HappaUni/HappaUniTests/HappaUniTests.swift`

**Interfaces:**
- Produces `SyncDocumentManifest`, `SyncService.sync(_:context:) async throws`, and `SyncService.restoreAll(context:) async throws -> SyncRestoreProgress`.

- [ ] **Step 1: Write failing tests**

```swift
@Test("Sync manifest round trips document metadata")
func roundTripsSyncManifest() throws {
    let document = LibraryDocument(name: "guide.md", url: URL(fileURLWithPath: "/tmp/guide.md"), size: 4, tags: ["课程"], folderID: UUID())
    let decoded = try JSONDecoder().decode(SyncDocumentManifest.self, from: JSONEncoder().encode(SyncDocumentManifest(document: document)))
    #expect(decoded.name == "guide.md")
    #expect(decoded.tags == ["课程"])
}
```

- [ ] **Step 2: Run focused test and verify RED**

Run the named test with `xcodebuild test -only-testing:`.

Expected: missing manifest type fails compilation.

- [ ] **Step 3: Implement sync manifest and conflict copy**

Upload a JSON manifest beside every document. Restore by recursively listing remote `documents/`, decoding manifests, and rebuilding missing local records. If a local document is newer, download the remote file under a `-recovered-<timestamp>` filename and retain local metadata. Report total/restored/conflicted counts to settings UI. Map only GitHub’s documented repository-exists response to an existing repository; expose other HTTP failures.

- [ ] **Step 4: Run focused tests and full suite**

Run the full iPad destination `xcodebuild test` command.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add HappaUni/HappaUni/Services/GitHubService.swift HappaUni/HappaUni/Services/SyncService.swift HappaUni/HappaUni/Views/SettingsView.swift HappaUni/HappaUniTests/HappaUniTests.swift
git commit -m "feat: add github metadata recovery"
git push
```

### Task 5: Persistent AI Chats and Streaming Responses

**Files:**
- Create: `HappaUni/HappaUni/Models/AIChatSession.swift`
- Modify: `HappaUni/HappaUni/HappaUniApp.swift`
- Modify: `HappaUni/HappaUni/Services/AIService.swift`
- Modify: `HappaUni/HappaUni/Views/AIChatView.swift`
- Test: `HappaUni/HappaUniTests/HappaUniTests.swift`

**Interfaces:**
- Produces `AIChatSession`, `AIChatMessage`, `AIService.streamChat(...) async throws -> AsyncThrowingStream<AIStreamEvent, Error>`, and PDF extraction through `AIContextExtractor.extract(from:)`.

- [ ] **Step 1: Write failing tests**

```swift
@Test("AI stream parser emits content and usage")
func parsesAIStream() throws {
    let events = try AIStreamParser.parse(data: Data("data: {\\\"choices\\\":[{\\\"delta\\\":{\\\"content\\\":\\\"你好\\\"}}]}\\n\\ndata: [DONE]\\n".utf8))
    #expect(events.contains(.text("你好")))
}
```

- [ ] **Step 2: Run focused test and verify RED**

Run the named test with `xcodebuild test -only-testing:`.

Expected: missing stream parser type fails compilation.

- [ ] **Step 3: Implement deterministic parser then integrate UI**

Parse OpenAI-compatible SSE `data:` lines, emit content deltas and final usage, tolerate blank keep-alives, and throw a typed error for malformed error payloads. Store session/message history in SwiftData. Extract PDF text with PDFKit; retain current markdown/text extraction. Cancel the active task when the chat view disappears.

- [ ] **Step 4: Run focused tests and full suite**

Run the full iPad destination `xcodebuild test` command.

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add HappaUni/HappaUni/Models/AIChatSession.swift HappaUni/HappaUni/HappaUniApp.swift HappaUni/HappaUni/Services/AIService.swift HappaUni/HappaUni/Views/AIChatView.swift HappaUni/HappaUniTests/HappaUniTests.swift
git commit -m "feat: persist streaming ai conversations"
git push
```

### Task 6: Structured Settings, UI Coverage, and Final Validation

**Files:**
- Modify: `HappaUni/HappaUni/Views/SettingsView.swift`
- Create: `HappaUni/HappaUni/Views/AppearanceSettingsView.swift`
- Create: `HappaUni/HappaUni/Views/BrowserSettingsView.swift`
- Create: `HappaUni/HappaUni/Views/StorageSettingsView.swift`
- Create: `HappaUni/HappaUni/Views/LaTeXSettingsView.swift`
- Modify: `HappaUni/HappaUniUITests/HappaUniUITests.swift`
- Modify: `HappaUni/HappaUniTests/HappaUniTests.swift`

**Interfaces:**
- Produces a `SettingsView` navigation list containing `通用与外观`, `AI 服务`, `GitHub 同步`, `WebDAV 账户`, `存储`, `浏览器`, and `LaTeX`.

- [ ] **Step 1: Write failing unit/UI tests**

```swift
@Test("Appearance preferences keep the selected reading font size")
func storesReadingFontSize() {
    let store = UserDefaults(suiteName: UUID().uuidString)!
    let settings = AppearanceSettings(store: store)
    settings.readingFontSize = 19
    #expect(AppearanceSettings(store: store).readingFontSize == 19)
}
```

Add an accessibility identifier `settings-root` to the settings navigation root and a UI test that opens it from the sidebar floating capsule.

- [ ] **Step 2: Run focused tests and verify RED**

Run the named unit test with `xcodebuild test -only-testing:`.

Expected: missing `AppearanceSettings` type fails compilation.

- [ ] **Step 3: Implement settings pages without global glass styling**

Persist non-secret appearance/browser/LaTeX preferences in UserDefaults. Keep credential screens using existing Keychain-backed services. Add managed WebDAV account entry points, cache clear/size controls, and LaTeX preview preferences. Preserve the existing bottom floating action capsule exactly as the Settings entry point.

- [ ] **Step 4: Run final verification**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project HappaUni/HappaUni.xcodeproj -scheme HappaUni -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild build -project HappaUni/HappaUni.xcodeproj -scheme HappaUni -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -quiet
git diff --check
git status --short
```

Expected: tests/build exit 0, no whitespace errors, and only current-task tracked files staged.

- [ ] **Step 5: Commit**

```bash
git add HappaUni/HappaUni/Views/SettingsView.swift HappaUni/HappaUni/Views/AppearanceSettingsView.swift HappaUni/HappaUni/Views/BrowserSettingsView.swift HappaUni/HappaUni/Views/StorageSettingsView.swift HappaUni/HappaUni/Views/LaTeXSettingsView.swift HappaUni/HappaUniUITests/HappaUniUITests.swift HappaUni/HappaUniTests/HappaUniTests.swift
git commit -m "feat: complete settings experience"
git push
```
