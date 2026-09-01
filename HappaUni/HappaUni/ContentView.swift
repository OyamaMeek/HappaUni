import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \LibraryDocument.modifiedAt, order: .reverse) private var documents: [LibraryDocument]
    @Query(sort: \WebDAVAccount.createdAt, order: .reverse) private var webDAVAccounts: [WebDAVAccount]
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @AppStorage("githubConnected") private var githubConnected = false
    @AppStorage("github.repository") private var githubRepository = "HappaUni-sync"

    @State private var selectedDocumentID: PersistentIdentifier?
    @State private var isImporting = false
    @State private var isShowingSettings = false
    @State private var isShowingAddWebDAV = false
    @State private var browsingWebDAVAccount: WebDAVAccount?
    @State private var editingWebDAVAccount: WebDAVAccount?
    @State private var editingDocument: LibraryDocument?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedFolderID: UUID?
    @State private var isBrowsingFolder = false
    @State private var isShowingAddFolder = false
    @State private var newFolderParentID: UUID?
    @State private var outlineDestination: DocumentOutlineItem.Destination?
    @State private var synchronizingDocumentIDs = Set<UUID>()
    @State private var pendingImport: PendingImport?

    private var folderNodes: [FolderTreeNode] { FolderTreeBuilder.make(from: folders) }
    private var filteredDocuments: [LibraryDocument] {
        documents.filter { document in
            !document.isArchived && matchesSearch(document)
        }
    }

    private var archivedDocuments: [LibraryDocument] {
        documents.filter { $0.isArchived && matchesSearch($0) }
    }

    private var selectedDocument: LibraryDocument? {
        documents.first { $0.persistentModelID == selectedDocumentID }
    }

    private var selectedFolderDocuments: [LibraryDocument] {
        guard let selectedFolderID else {
            return filteredDocuments.filter { $0.folderID == nil }
        }
        let folderIDs = FolderTreeBuilder.descendantIDs(of: selectedFolderID, in: folders)
        return filteredDocuments.filter { $0.folderID.map(folderIDs.contains) ?? false }
    }

    private var selectedDocumentSupportsOutline: Bool {
        selectedDocument?.type == .pdf || selectedDocument?.type == .markdown
    }

    var body: some View {
        NavigationSplitView {
            if let selectedDocument, selectedDocumentSupportsOutline {
                DocumentOutlineView(document: selectedDocument) { destination in
                    outlineDestination = destination
                }
            } else {
                sidebar
                    .navigationTitle("资料库")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            LibraryAddMenu(
                                onImport: { isImporting = true },
                                onCreateFolder: {
                                    newFolderParentID = selectedFolderID
                                    isShowingAddFolder = true
                                }
                            )
                        }
                    }
            }
        } detail: {
            if let selectedDocument {
                DocumentReaderView(
                    document: selectedDocument,
                    onBack: { selectedDocumentID = nil },
                    outlineDestination: $outlineDestination
                )
            } else if isBrowsingFolder {
                FolderLibraryView(
                    title: selectedFolderID.flatMap { id in folders.first(where: { $0.id == id })?.name } ?? "未归档",
                    documents: selectedFolderDocuments,
                    onSelect: { selectedDocumentID = $0.persistentModelID }
                )
            } else {
                WelcomeView(onImport: { isImporting = true })
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf, .plainText, .utf8PlainText, .image, .epub, Self.texContentType],
            allowsMultipleSelection: true
        ) { result in
            prepareImport(result)
        }
        .sheet(item: $pendingImport) { pending in
            ImportDestinationPickerView(
                fileCount: pending.urls.count,
                folders: folders,
                onSelect: { folderID in commitImport(pending, folderID: folderID) },
                onCancel: { discardPendingImport(pending) }
            )
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .task {
            repairStoredDocumentLocations()
        }
        .task(id: selectedDocumentID) {
            outlineDestination = nil
            guard let selectedDocument else { return }
            do {
                try await SyncService.shared.syncFileOnOpen(selectedDocument, folders: folders, repository: githubRepository)
                try modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .onChange(of: selectedDocumentID) { previousID, currentID in
            guard
                previousID != currentID,
                let previousID,
                let document = documents.first(where: { $0.persistentModelID == previousID })
            else {
                return
            }
            synchronizeEditedDocument(document)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase != .active, let selectedDocument else { return }
            synchronizeEditedDocument(selectedDocument)
        }
        .sheet(isPresented: $isShowingAddWebDAV) {
            AddWebDAVAccountView()
        }
        .sheet(item: $editingWebDAVAccount) { account in
            AddWebDAVAccountView(account: account)
        }
        .sheet(item: $browsingWebDAVAccount) { account in
            WebDAVBrowserView(account: account)
        }
        .sheet(item: $editingDocument) { document in
            MetadataEditorView(document: document)
        }
        .sheet(isPresented: $isShowingAddFolder) {
            AddFolderView(parentID: newFolderParentID)
        }
        .alert("导入失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private struct PendingImport: Identifiable {
        let id = UUID()
        let directory: URL
        let urls: [URL]
    }

    private static let texContentType = UTType(filenameExtension: "tex") ?? .plainText

    private func synchronizeEditedDocument(_ document: LibraryDocument) {
        guard synchronizingDocumentIDs.insert(document.id).inserted else { return }
        PDFAnnotationStore.flush(for: document.url)

        let backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "同步 \(document.name)") {}
        let webDAVAccounts = webDAVAccounts
        let repository = githubRepository

        Task {
            await SyncService.shared.syncEditedDocument(
                document,
                documents: documents,
                folders: folders,
                webDAVAccounts: webDAVAccounts,
                repository: repository
            )
            try? modelContext.save()
            synchronizingDocumentIDs.remove(document.id)
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
        }
    }

    private var sidebar: some View {
        List(selection: $selectedDocumentID) {
            Section("自动备份") {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub 同步")
                        Text(githubConnected ? "已连接，等待同步" : "未连接")
                            .font(.caption)
                            .foregroundStyle(githubConnected ? .green : .secondary)
                    }
                } icon: {
                    Image(systemName: githubConnected ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                        .foregroundStyle(githubConnected ? .green : .orange)
                }
            }

            Section("云端存储") {
                ForEach(webDAVAccounts) { account in
                    Button {
                        browsingWebDAVAccount = account
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                Text(account.serverAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "externaldrive.fill.badge.icloud")
                                .foregroundStyle(.cyan)
                        }
                    }
                    .contextMenu {
                        Button {
                            editingWebDAVAccount = account
                        } label: {
                            Label("编辑服务器", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(account)
                        } label: {
                            Label("删除服务器", systemImage: "trash")
                        }
                    }
                }
                Button {
                    isShowingAddWebDAV = true
                } label: {
                    Label("添加 WebDAV 服务器", systemImage: "externaldrive.badge.plus")
                }
            }

            Section {
                Button {
                    selectedDocumentID = nil
                    selectedFolderID = nil
                    isBrowsingFolder = true
                } label: {
                    FolderSidebarRow(
                        name: "未归档",
                        color: .gray,
                        count: filteredDocuments.filter { $0.folderID == nil }.count,
                        isSelected: selectedFolderID == nil
                    )
                }
                .buttonStyle(.plain)

                FolderTreeRows(
                    nodes: folderNodes,
                    documents: filteredDocuments,
                    allFolders: folders,
                    selectedFolderID: $selectedFolderID,
                    selectedDocumentID: $selectedDocumentID,
                    isBrowsingFolder: $isBrowsingFolder,
                    editingDocument: $editingDocument,
                    onAddSubfolder: { folder in
                        newFolderParentID = folder.id
                        isShowingAddFolder = true
                    },
                    onDeleteFolder: deleteFolder,
                    onArchiveDocument: archive,
                    onDeleteDocument: delete
                )
            } header: {
                HStack {
                    Text("文件夹")
                    Spacer()
                    Button { newFolderParentID = nil; isShowingAddFolder = true } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建文件夹")
                }
            }

            if !archivedDocuments.isEmpty {
                Section("归档") {
                    ForEach(archivedDocuments) { document in
                        documentRow(document)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索文件")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    selectedFolderID = nil
                    isBrowsingFolder = false
                    searchText = ""
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "books.vertical.fill")
                            .font(.title3.weight(.semibold))
                        Text("资料库")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)

                Button {
                    isShowingSettings = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.title3.weight(.semibold))
                        Text("设置")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.34), .white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.26), radius: 18, y: 10)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    private func documentRow(_ document: LibraryDocument) -> some View {
        LibrarySidebarDocumentRow(
            document: document,
            editingDocument: $editingDocument,
            onArchive: archive,
            onDelete: delete
        )
            .tag(document.persistentModelID)
    }

    private func matchesSearch(_ document: LibraryDocument) -> Bool {
        searchText.isEmpty
            || document.name.localizedCaseInsensitiveContains(searchText)
            || document.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private func prepareImport(_ result: Result<[URL], Error>) {
        do {
            let sourceURLs = try result.get()
            let securityScopedURLs = sourceURLs.filter { $0.startAccessingSecurityScopedResource() }
            defer { securityScopedURLs.forEach { $0.stopAccessingSecurityScopedResource() } }

            let stagingDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("HappaUniImport-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            var stagedURLs: [URL] = []
            do {
                for sourceURL in sourceURLs {
                    let destination = uniqueImportURL(in: stagingDirectory, filename: sourceURL.lastPathComponent)
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    stagedURLs.append(destination)
                }
                pendingImport = PendingImport(directory: stagingDirectory, urls: stagedURLs)
            } catch {
                try? FileManager.default.removeItem(at: stagingDirectory)
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitImport(_ pending: PendingImport, folderID: UUID?) {
        defer { try? FileManager.default.removeItem(at: pending.directory) }
        do {
            let fileService = FileService()
            let importedFiles = try fileService.importFiles(pending.urls, into: fileService.documentsDirectory())
            let importedDocuments = importedFiles.map { $0.makeDocument(folderID: folderID) }
            for document in importedDocuments { modelContext.insert(document) }
            do {
                try modelContext.save()
                selectedDocumentID = importedDocuments.last?.persistentModelID
            } catch {
                for importedFile in importedFiles { try? FileManager.default.removeItem(at: importedFile.url) }
                modelContext.rollback()
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardPendingImport(_ pending: PendingImport) {
        try? FileManager.default.removeItem(at: pending.directory)
    }

    private func uniqueImportURL(in directory: URL, filename: String) -> URL {
        let fileManager = FileManager.default
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: filename).pathExtension
        var candidate = directory.appendingPathComponent(filename)
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(index))" + (ext.isEmpty ? "" : ".\(ext)"))
            index += 1
        }
        return candidate
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets { delete(filteredDocuments[index]) }
    }

    private func repairStoredDocumentLocations() {
        do {
            let fileService = FileService()
            let migratedPaths = try fileService.migrateLegacyLibraryDirectory()
            var didChange = false

            for document in documents {
                if let migratedPath = migratedPaths[document.path], document.path != migratedPath {
                    document.path = migratedPath
                    didChange = true
                } else if let resolvedURL = fileService.resolvedURL(for: document),
                          document.path != resolvedURL.path {
                    document.path = resolvedURL.path
                    didChange = true
                }
            }

            if didChange {
                try modelContext.save()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ document: LibraryDocument) {
        do {
            try FileService().delete(document)
            if selectedDocumentID == document.persistentModelID { selectedDocumentID = nil }
            modelContext.delete(document)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func archive(_ document: LibraryDocument) {
        do {
            document.isArchived.toggle()
            document.modifiedAt = .now
            if document.isArchived && selectedDocumentID == document.persistentModelID {
                selectedDocumentID = nil
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteFolder(_ folder: LibraryFolder) {
        do {
            for document in documents where document.folderID == folder.id {
                document.folderID = nil
            }
            for child in folders where child.parentID == folder.id {
                child.parentID = folder.parentID
            }
            if selectedFolderID == folder.id { selectedFolderID = nil }
            modelContext.delete(folder)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ account: WebDAVAccount) {
        do {
            try KeychainStore().delete(account.passwordKey)
            modelContext.delete(account)
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


private struct ImportDestinationPickerView: View {
    let fileCount: Int
    let folders: [LibraryFolder]
    let onSelect: (UUID?) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("导入位置") {
                    Button {
                        onSelect(nil)
                        dismiss()
                    } label: {
                        Label("未归档", systemImage: "tray")
                    }

                    FolderDestinationRows(nodes: FolderTreeBuilder.make(from: folders), onSelect: { folderID in
                        onSelect(folderID)
                        dismiss()
                    })
                }
            }
            .navigationTitle("选择文件夹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("将导入 \(fileCount) 个文件")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
    }
}

private struct FolderDestinationRows: View {
    let nodes: [FolderTreeNode]
    let onSelect: (UUID) -> Void

    var body: some View {
        ForEach(nodes) { node in
            Button { onSelect(node.folder.id) } label: {
                Label(node.folder.name, systemImage: "folder")
            }
            FolderDestinationRows(nodes: node.children, onSelect: onSelect)
                .padding(.leading, 20)
        }
    }
}

private struct FolderTreeRows: View {
    let nodes: [FolderTreeNode]
    let documents: [LibraryDocument]
    let allFolders: [LibraryFolder]
    @Binding var selectedFolderID: UUID?
    @Binding var selectedDocumentID: PersistentIdentifier?
    @Binding var isBrowsingFolder: Bool
    @Binding var editingDocument: LibraryDocument?
    let onAddSubfolder: (LibraryFolder) -> Void
    let onDeleteFolder: (LibraryFolder) -> Void
    let onArchiveDocument: (LibraryDocument) -> Void
    let onDeleteDocument: (LibraryDocument) -> Void

    var body: some View {
        ForEach(nodes) { node in
            DisclosureGroup {
                ForEach(documents.filter { $0.folderID == node.folder.id }) { document in
                    LibrarySidebarDocumentRow(
                        document: document,
                        editingDocument: $editingDocument,
                        onArchive: onArchiveDocument,
                        onDelete: onDeleteDocument
                    )
                    .tag(document.persistentModelID)
                }
                FolderTreeRows(
                    nodes: node.children,
                    documents: documents,
                    allFolders: allFolders,
                    selectedFolderID: $selectedFolderID,
                    selectedDocumentID: $selectedDocumentID,
                    isBrowsingFolder: $isBrowsingFolder,
                    editingDocument: $editingDocument,
                    onAddSubfolder: onAddSubfolder,
                    onDeleteFolder: onDeleteFolder,
                    onArchiveDocument: onArchiveDocument,
                    onDeleteDocument: onDeleteDocument
                )
            } label: {
                Button {
                    selectedDocumentID = nil
                    selectedFolderID = node.folder.id
                    isBrowsingFolder = true
                } label: {
                    FolderSidebarRow(
                        name: node.folder.name,
                        color: FolderAccent.color(for: node.folder.id),
                        count: documentCount(includingDescendantsOf: node.folder.id),
                        isSelected: selectedFolderID == node.folder.id
                    )
                }
                .buttonStyle(.plain)
            }
            .contextMenu {
                Button { onAddSubfolder(node.folder) } label: {
                    Label("新建子文件夹", systemImage: "folder.badge.plus")
                }
                Button(role: .destructive) { onDeleteFolder(node.folder) } label: {
                    Label("删除文件夹", systemImage: "trash")
                }
            }
        }
    }

    private func documentCount(includingDescendantsOf folderID: UUID) -> Int {
        let ids = Set(FolderTreeBuilder.descendantIDs(of: folderID, in: allFolders))
        return documents.filter { $0.folderID.map(ids.contains) ?? false }.count
    }
}

private struct FolderSidebarRow: View {
    let name: String
    let color: Color
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(color).frame(width: 14, height: 14)
            Text(name).lineLimit(1)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private enum FolderAccent {
    static func color(for id: UUID) -> Color {
        let colors: [Color] = [.yellow, .orange, .red, .pink, .purple, .blue, .green]
        return colors[abs(id.uuidString.hashValue) % colors.count]
    }
}

private struct LibrarySidebarDocumentRow: View {
    let document: LibraryDocument
    @Binding var editingDocument: LibraryDocument?
    let onArchive: (LibraryDocument) -> Void
    let onDelete: (LibraryDocument) -> Void

    var body: some View {
        DocumentRow(document: document)
            .contextMenu {
                Button {
                    editingDocument = document
                } label: {
                    Label("编辑标签", systemImage: "tag")
                }
                Button {
                    onArchive(document)
                } label: {
                    Label(
                        document.isArchived ? "取消归档" : "归档",
                        systemImage: document.isArchived ? "tray.and.arrow.up" : "archivebox"
                    )
                }
                Button(role: .destructive) {
                    onDelete(document)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
    }
}

private struct LibraryAddMenu: View {
    let onImport: () -> Void
    let onCreateFolder: () -> Void

    @State private var isPresented = false
    @State private var pendingAction: (() -> Void)?

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("资料库操作")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 10) {
                actionButton(
                    title: "导入",
                    systemImage: "square.and.arrow.down",
                    action: onImport
                )
                actionButton(
                    title: "新建文件夹",
                    systemImage: "folder.badge.plus",
                    action: onCreateFolder
                )
            }
            .padding(12)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.48), .white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: isPresented) { _, isVisible in
            guard !isVisible, let action = pendingAction else { return }
            pendingAction = nil
            DispatchQueue.main.async(execute: action)
        }
    }

    @ViewBuilder
    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            pendingAction = action
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.body.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(minWidth: 132, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

private struct AddFolderView: View {
    let parentID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("文件夹名称", text: $name)
            }
            .navigationTitle("新建文件夹")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        modelContext.insert(LibraryFolder(name: trimmed, parentID: parentID))
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DocumentRow: View {
    let document: LibraryDocument

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                    .lineLimit(1)
                Text("\(document.type.displayName) · \(document.formattedSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: document.type.iconName)
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch document.type {
        case .pdf: .red
        case .markdown, .tex, .text: .blue
        case .epub: .orange
        case .image: .purple
        case .other: .secondary
        }
    }
}


private struct FolderLibraryView: View {
    let title: String
    let documents: [LibraryDocument]
    let onSelect: (LibraryDocument) -> Void

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 18)]

    var body: some View {
        Group {
            if documents.isEmpty {
                ContentUnavailableView(
                    "\(title)为空",
                    systemImage: "folder",
                    description: Text("导入文件时可将资料放入此文件夹。")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(documents) { document in
                            Button { onSelect(document) } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    Image(systemName: document.type.iconName)
                                        .font(.system(size: 34, weight: .medium))
                                        .foregroundStyle(folderDocumentColor(for: document.type))
                                        .frame(maxWidth: .infinity, minHeight: 110)
                                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    Text(document.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(document.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1) }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .navigationTitle(title)
    }

    private func folderDocumentColor(for type: DocumentType) -> Color {
        switch type {
        case .pdf: .red
        case .markdown, .tex, .text: .blue
        case .epub: .orange
        case .image: .purple
        case .other: .secondary
        }
    }
}

private struct WelcomeView: View {
    let onImport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("欢迎使用 HappaUni", systemImage: "books.vertical.fill")
        } description: {
            Text("导入 PDF、Markdown、EPUB、文本或图片，开始建立你的本地资料库。")
        } actions: {
            Button("导入文件", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [LibraryDocument.self, LibraryFolder.self, WebDAVAccount.self], inMemory: true)
}
