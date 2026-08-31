import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
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
    @State private var editingDocument: LibraryDocument?
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedFolderID: UUID?
    @State private var isShowingAddFolder = false
    @State private var newFolderParentID: UUID?

    private var folderNodes: [FolderTreeNode] { FolderTreeBuilder.make(from: folders) }

    private var filteredDocuments: [LibraryDocument] {
        documents.filter { document in
            let matchesFolder = selectedFolderID == nil || document.folderID == selectedFolderID
            let matchesSearch = searchText.isEmpty || document.name.localizedCaseInsensitiveContains(searchText) || document.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            return matchesFolder && matchesSearch
        }
    }

    private var selectedDocument: LibraryDocument? {
        documents.first { $0.persistentModelID == selectedDocumentID }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("资料库")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { isImporting = true } label: {
                            Label("导入文件", systemImage: "plus")
                        }
                    }
                }
        } detail: {
            if let selectedDocument {
                DocumentReaderView(document: selectedDocument)
            } else {
                WelcomeView(onImport: { isImporting = true })
            }
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf, .plainText, .utf8PlainText, .image, .epub],
            allowsMultipleSelection: true
        ) { result in
            importFiles(result)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .task(id: selectedDocumentID) {
            guard let selectedDocument else { return }
            do {
                try await SyncService.shared.syncFileOnOpen(selectedDocument, repository: githubRepository)
                try modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingAddWebDAV) {
            AddWebDAVAccountView()
        }
        .sheet(item: $browsingWebDAVAccount) { account in
            WebDAVBrowserView(account: account)
        }
        .sheet(item: $editingDocument) { document in
            DocumentMetadataEditor(document: document)
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

            Section("文件夹") {
                Button {
                    selectedFolderID = nil
                } label: {
                    Label("全部资料", systemImage: selectedFolderID == nil ? "folder.fill" : "folder")
                }
                OutlineGroup(folderNodes, children: \.optionalChildren) { node in
                    Button {
                        selectedFolderID = node.folder.id
                    } label: {
                        Label(node.folder.name, systemImage: selectedFolderID == node.folder.id ? "folder.fill" : "folder")
                    }
                    .contextMenu {
                        Button {
                            newFolderParentID = node.folder.id
                            isShowingAddFolder = true
                        } label: {
                            Label("新建子文件夹", systemImage: "folder.badge.plus")
                        }
                        Button(role: .destructive) {
                            deleteFolder(node.folder)
                        } label: {
                            Label("删除文件夹", systemImage: "trash")
                        }
                    }
                }
            }

            Section("本地文件") {
                if filteredDocuments.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredDocuments) { document in
                        DocumentRow(document: document)
                            .tag(document.persistentModelID)
                            .contextMenu {
                                Button {
                                    editingDocument = document
                                } label: {
                                    Label("编辑标签", systemImage: "tag")
                                }
                                Button(role: .destructive) {
                                    delete(document)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteDocuments)
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索文件")
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    newFolderParentID = selectedFolderID
                    isShowingAddFolder = true
                } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }

                Spacer(minLength: 0)

                Button {
                    isShowingSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            for sourceURL in try result.get() {
                let didAccess = sourceURL.startAccessingSecurityScopedResource()
                defer {
                    if didAccess { sourceURL.stopAccessingSecurityScopedResource() }
                }
                let document = try FileService().importDocument(from: sourceURL)
                modelContext.insert(document)
                selectedDocumentID = document.persistentModelID
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteDocuments(at offsets: IndexSet) {
        for index in offsets { delete(filteredDocuments[index]) }
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


private struct DocumentMetadataEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var document: LibraryDocument
    @Query(sort: \LibraryFolder.name) private var folders: [LibraryFolder]
    @State private var tagsText = ""
    @State private var selectedFolderID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section("标签") {
                    TextField("用逗号分隔，例如：课程, 论文", text: $tagsText)
                    Text("标签会参与资料库搜索。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("文件夹") {
                    Picker("位置", selection: $selectedFolderID) {
                        Text("未分类").tag(UUID?.none)
                        ForEach(folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                }
                Section("资料") {
                    LabeledContent("类型", value: document.type.displayName)
                    LabeledContent("大小", value: document.formattedSize)
                }
            }
            .navigationTitle("资料信息")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        document.tags = tagsText.split(separator: ",").map(String.init)
                        document.folderID = selectedFolderID
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .task {
                tagsText = document.tags.joined(separator: ", ")
                selectedFolderID = document.folderID
            }
        }
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
        case .markdown, .text: .blue
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
