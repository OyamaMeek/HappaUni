import SwiftData
import SwiftUI

struct WebDAVBrowserView: View {
    let account: WebDAVAccount

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var path = "/"
    @State private var files: [WebDAVFile] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadingPath: String?
    @State private var isShowingUpload = false
    @State private var isShowingNewFolder = false
    @State private var newFolderName = ""
    @State private var pendingDelete: WebDAVFile?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && files.isEmpty {
                    ProgressView("正在读取 WebDAV 文件夹…")
                } else if files.isEmpty {
                    ContentUnavailableView("文件夹为空", systemImage: "folder")
                } else {
                    List(files) { file in
                        if file.isDirectory {
                            Button {
                                path = file.path
                                loadFiles()
                            } label: {
                                FileRow(file: file)
                            }
                            .contextMenu {
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    pendingDelete = file
                                }
                            }
                        } else {
                            Button {
                                download(file)
                            } label: {
                                HStack {
                                    FileRow(file: file)
                                    if downloadingPath == file.path { ProgressView() }
                                }
                            }
                            .disabled(downloadingPath != nil)
                            .contextMenu {
                                Button("删除", systemImage: "trash", role: .destructive) {
                                    pendingDelete = file
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(account.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        path = parentPath
                        loadFiles()
                    } label: {
                        Label("上级", systemImage: "chevron.up")
                    }
                    .disabled(path == "/")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { isShowingUpload = true } label: {
                        Label("上传资料", systemImage: "square.and.arrow.up")
                    }
                    Button { isShowingNewFolder = true } label: {
                        Label("新建文件夹", systemImage: "folder.badge.plus")
                    }
                    Button(action: loadFiles) { Label("刷新", systemImage: "arrow.clockwise") }
                }
            }
            .sheet(isPresented: $isShowingUpload) {
                WebDAVUploadView(account: account, path: path) { loadFiles() }
            }
            .task {
                loadFiles()
                await resumeQueuedUploads()
            }
            .alert("新建文件夹", isPresented: $isShowingNewFolder) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) { newFolderName = "" }
                Button("创建") { createDirectory() }
            } message: {
                Text("将在当前 WebDAV 目录中创建文件夹。")
            }
            .confirmationDialog(
                "删除“\(pendingDelete?.name ?? "")”？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let file = pendingDelete { delete(file) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("此操作会删除远端文件或文件夹。")
            }
            .alert("WebDAV", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var parentPath: String {
        let components = path.split(separator: "/")
        guard components.count > 1 else { return "/" }
        return "/" + components.dropLast().joined(separator: "/")
    }

    private func loadFiles() {
        guard let serverURL = account.serverURL else { errorMessage = "服务器地址无效。"; return }
        isLoading = true
        Task {
            do {
                guard let password = try KeychainStore().value(for: account.passwordKey) else { throw BrowserError.missingPassword }
                files = try await WebDAVService.shared.listDirectory(url: serverURL, username: account.username, password: password, path: path)
                    .sorted {
                        if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func download(_ file: WebDAVFile) {
        guard let serverURL = account.serverURL else { errorMessage = "服务器地址无效。"; return }
        downloadingPath = file.path
        Task {
            defer { downloadingPath = nil }
            do {
                guard let password = try KeychainStore().value(for: account.passwordKey) else { throw BrowserError.missingPassword }
                let temporaryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(URL(fileURLWithPath: file.name).pathExtension)
                try await WebDAVService.shared.download(
                    url: WebDAVRemotePath.requestURL(serverURL: serverURL, href: file.path),
                    username: account.username,
                    password: password,
                    to: temporaryURL
                )
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                let data = try Data(contentsOf: temporaryURL)
                _ = try WebDAVCacheStore().store(data, accountID: account.id, remotePath: file.path)
                let document = try FileService().importDocument(from: temporaryURL)
                modelContext.insert(document)
                try modelContext.save()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createDirectory() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolderName = ""
        guard !name.isEmpty else { return }
        guard !name.contains("/") else {
            errorMessage = "文件夹名称不能包含斜杠。"
            return
        }
        guard let serverURL = account.serverURL else {
            errorMessage = "服务器地址无效。"
            return
        }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                guard let password = try KeychainStore().value(for: account.passwordKey) else { throw BrowserError.missingPassword }
                let remotePath = WebDAVRemotePath.join(base: path, child: name)
                try await WebDAVService.shared.makeDirectory(
                    at: WebDAVRemotePath.url(serverURL: serverURL, path: remotePath),
                    username: account.username,
                    password: password
                )
                loadFiles()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ file: WebDAVFile) {
        guard let serverURL = account.serverURL else {
            errorMessage = "服务器地址无效。"
            return
        }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                guard let password = try KeychainStore().value(for: account.passwordKey) else { throw BrowserError.missingPassword }
                try await WebDAVService.shared.delete(
                    at: WebDAVRemotePath.requestURL(serverURL: serverURL, href: file.path),
                    username: account.username,
                    password: password,
                    eTag: file.eTag
                )
                loadFiles()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resumeQueuedUploads() async {
        guard let serverURL = account.serverURL,
              let password = try? KeychainStore().value(for: account.passwordKey) else {
            return
        }

        let queue = WebDAVUploadQueue.shared
        for upload in queue.items(for: account.id) {
            guard FileManager.default.fileExists(atPath: upload.localPath) else {
                queue.remove(upload.id)
                continue
            }
            do {
                try await WebDAVService.shared.upload(
                    data: Data(contentsOf: upload.localURL),
                    to: WebDAVRemotePath.url(serverURL: serverURL, path: upload.remotePath),
                    username: account.username,
                    password: password
                )
                queue.remove(upload.id)
            } catch {
                queue.markAttempt(upload.id)
            }
        }
    }

    private enum BrowserError: LocalizedError {
        case missingPassword
        var errorDescription: String? { "找不到此服务器的密码，请重新添加账户。" }
    }
}

private struct FileRow: View {
    let file: WebDAVFile

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                if !file.isDirectory {
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: file.isDirectory ? "folder.fill" : DocumentType.detect(from: file.name).iconName)
                .foregroundStyle(file.isDirectory ? .yellow : .blue)
        }
    }
}

private struct WebDAVUploadView: View {
    let account: WebDAVAccount
    let path: String
    let onUploaded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LibraryDocument.modifiedAt, order: .reverse) private var documents: [LibraryDocument]
    @State private var uploadingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if documents.isEmpty {
                    ContentUnavailableView("没有可上传的资料", systemImage: "doc.badge.plus")
                } else {
                    List(documents) { document in
                        Button { upload(document) } label: {
                            HStack {
                                FileDocumentRow(document: document)
                                Spacer()
                                if uploadingID == document.id { ProgressView() }
                            }
                        }
                        .disabled(uploadingID != nil)
                    }
                }
            }
            .navigationTitle("上传到 \(path)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .alert("WebDAV 上传", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func upload(_ document: LibraryDocument) {
        guard let serverURL = account.serverURL else { errorMessage = "服务器地址无效。"; return }
        let remotePath = WebDAVRemotePath.join(base: path, child: document.name)
        uploadingID = document.id
        Task {
            defer { uploadingID = nil }
            do {
                guard let password = try KeychainStore().value(for: account.passwordKey) else { throw UploadError.missingPassword }
                try await WebDAVService.shared.upload(
                    data: Data(contentsOf: document.url),
                    to: WebDAVRemotePath.url(serverURL: serverURL, path: remotePath),
                    username: account.username,
                    password: password
                )
                onUploaded()
                dismiss()
            } catch {
                WebDAVUploadQueue.shared.enqueue(
                    accountID: account.id,
                    localURL: document.url,
                    remotePath: remotePath
                )
                errorMessage = "\(error.localizedDescription) 已加入待上传队列，下次打开此服务器时会自动重试。"
            }
        }
    }

    private enum UploadError: LocalizedError {
        case missingPassword
        var errorDescription: String? { "找不到此服务器的密码，请重新添加账户。" }
    }
}

private struct FileDocumentRow: View {
    let document: LibraryDocument

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(document.name)
                Text(document.formattedSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: document.type.iconName)
                .foregroundStyle(.blue)
        }
    }
}
