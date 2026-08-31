import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var documents: [LibraryDocument]
    @Query private var folders: [LibraryFolder]
    @AppStorage("aiConfigured") private var aiConfigured = false
    @AppStorage("ai.baseURL") private var aiBaseURL = "https://api.openai.com/v1"
    @AppStorage("ai.model") private var aiModel = "gpt-4o-mini"
    @AppStorage("githubConnected") private var githubConnected = false
    @AppStorage("github.repository") private var repository = "HappaUni-sync"
    @State private var apiKey = ""
    @State private var githubToken = ""
    @State private var isConnectingGitHub = false
    @State private var isRestoring = false
    @State private var isBackingUpMetadata = false
    @State private var cacheSize = "0 KB"
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 功能") {
                    SecureField("OpenAI API Key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("API 地址", text: $aiBaseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField("模型", text: $aiModel)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("保存 AI 设置", action: saveAIConfiguration)
                    Text(aiConfigured ? "API Key 已保存在本机钥匙串。" : "配置后可在文档阅读页使用 AI 问答。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("GitHub 自动备份") {
                    SecureField("Personal Access Token", text: $githubToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("仓库名称", text: $repository)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        connectGitHub()
                    } label: {
                        HStack {
                            Text(githubConnected ? "更新 GitHub 连接" : "连接 GitHub")
                            Spacer()
                            if isConnectingGitHub { ProgressView() }
                        }
                    }
                    .disabled(isConnectingGitHub)
                    if githubConnected {
                        Button {
                            backupMetadataToGitHub()
                        } label: {
                            HStack {
                                Text("备份资料库元数据")
                                Spacer()
                                if isBackingUpMetadata { ProgressView() }
                            }
                        }
                        .disabled(isBackingUpMetadata)
                        Button {
                            restoreFromGitHub()
                        } label: {
                            HStack {
                                Text("从 GitHub 恢复资料库")
                                Spacer()
                                if isRestoring { ProgressView() }
                            }
                        }
                        .disabled(isRestoring)
                        Button("断开 GitHub", role: .destructive, action: disconnectGitHub)
                    }
                    Text("连接后，打开未同步的本地文档会自动备份到仓库；可同时备份文件夹、标签和资料状态，换设备后恢复。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("存储与缓存") {
                    LabeledContent("WebDAV 缓存", value: cacheSize)
                    Button("清除 WebDAV 缓存", role: .destructive, action: clearWebDAVCache)
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.0.0")
                    LabeledContent("资料库", value: "本地优先")
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                loadCredentials()
                refreshCacheSize()
            }
            .alert("设置", isPresented: Binding(
                get: { message != nil }, set: { if !$0 { message = nil } }
            )) {
                Button("确定", role: .cancel) { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func loadCredentials() {
        apiKey = (try? KeychainStore().value(for: "openai.apiKey")) ?? ""
        githubToken = (try? KeychainStore().value(for: "github.accessToken")) ?? ""
    }

    private func saveAIConfiguration() {
        do {
            guard URL(string: aiBaseURL) != nil else { throw SettingsError.invalidAIURL }
            try KeychainStore().save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "openai.apiKey")
            aiConfigured = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            message = "AI 设置已保存。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func connectGitHub() {
        let token = githubToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "请输入 GitHub Token 和仓库名称。"
            return
        }
        isConnectingGitHub = true
        Task {
            do {
                try await GitHubService.shared.saveAccessToken(token)
                try await GitHubService.shared.ensureRepository(named: repository)
                githubConnected = true
                message = "GitHub 已连接。"
            } catch {
                message = error.localizedDescription
            }
            isConnectingGitHub = false
        }
    }

    private func disconnectGitHub() {
        do {
            try GitHubService.shared.signOut()
            githubToken = ""
            githubConnected = false
        } catch {
            message = error.localizedDescription
        }
    }

    private func restoreFromGitHub() {
        isRestoring = true
        Task {
            defer { isRestoring = false }
            do {
                let metadata = try await SyncService.shared.restoreMetadata(repository: repository)
                let summary = try await SyncService.shared.restoreDocuments(repository: repository, existingDocuments: documents)
                for document in summary.restored {
                    modelContext.insert(document)
                }
                if let metadata {
                    let existingFolderIDs = Set(folders.map(\.id))
                    for folder in metadata.folders where !existingFolderIDs.contains(folder.id) {
                        modelContext.insert(
                            LibraryFolder(
                                id: folder.id,
                                name: folder.name,
                                parentID: folder.parentID,
                                createdAt: folder.createdAt
                            )
                        )
                    }
                    SyncService.shared.apply(metadata, to: documents + summary.restored)
                }
                if !summary.restored.isEmpty || metadata != nil {
                    try modelContext.save()
                }
                var result = "已恢复 \(summary.restored.count) 份资料。"
                if metadata != nil { result += " 已恢复文件夹和标签。"}
                if !summary.conflicts.isEmpty {
                    result += " \(summary.conflicts.count) 份本地修改资料已保留。"
                }
                message = result
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func backupMetadataToGitHub() {
        isBackingUpMetadata = true
        Task {
            defer { isBackingUpMetadata = false }
            do {
                try await SyncService.shared.backupMetadata(
                    documents: documents,
                    folders: folders,
                    repository: repository
                )
                message = "资料库元数据已备份到 GitHub。"
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func clearWebDAVCache() {
        do {
            try WebDAVCacheStore().clear()
            refreshCacheSize()
            message = "WebDAV 缓存已清除。"
        } catch {
            message = error.localizedDescription
        }
    }

    private func refreshCacheSize() {
        cacheSize = ByteCountFormatter.string(fromByteCount: WebDAVCacheStore().size(), countStyle: .file)
    }

    private enum SettingsError: LocalizedError {
        case invalidAIURL
        var errorDescription: String? { "请输入有效的 AI API 地址。" }
    }
}
