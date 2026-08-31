import SwiftData
import SwiftUI

struct AddWebDAVAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let account: WebDAVAccount?
    @State private var name: String
    @State private var serverAddress: String
    @State private var username: String
    @State private var password: String
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    init(account: WebDAVAccount? = nil) {
        self.account = account
        _name = State(initialValue: account?.name ?? "")
        _serverAddress = State(initialValue: account?.serverAddress ?? "")
        _username = State(initialValue: account?.username ?? "")
        _password = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("名称", text: $name)
                    TextField("https://dav.example.com/", text: $serverAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }
                Section("登录信息") {
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(account == nil ? "密码或应用专用密码" : "新密码（留空则保持不变）", text: $password)
                }
                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("测试连接")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting)

                    if let statusMessage {
                        Label(statusMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } footer: {
                    Text("密码仅保存在本机钥匙串，不会写入资料库数据库。")
                }
            }
            .navigationTitle(account == nil ? "添加 WebDAV" : "编辑 WebDAV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving)
                }
            }
            .alert("WebDAV 配置", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var input: WebDAVAccountInput {
        WebDAVAccountInput(name: name, serverAddress: serverAddress, username: username, password: password)
    }

    private func testConnection() {
        isTesting = true
        statusMessage = nil
        Task {
            do {
                let url = try input.validatedURL()
                let password = try effectivePassword()
                try input.validateCredentials(with: password)
                try await WebDAVService().testConnection(url: url, username: username, password: password)
                statusMessage = "连接成功"
            } catch {
                errorMessage = error.localizedDescription
            }
            isTesting = false
        }
    }

    private func save() {
        isSaving = true
        Task {
            var newAccount: WebDAVAccount?
            do {
                let accountName = try input.validatedName()
                let url = try input.validatedURL()
                let password = try effectivePassword()
                try input.validateCredentials(with: password)
                try await WebDAVService.shared.ensureDirectory(
                    serverURL: url,
                    username: username,
                    password: password,
                    path: WebDAVRemotePath.libraryRoot
                )
                if let account {
                    account.name = accountName
                    account.serverAddress = url.absoluteString
                    account.username = username
                    if !self.password.isEmpty {
                        try KeychainStore().save(password, for: account.passwordKey)
                    }
                } else {
                    let account = WebDAVAccount(name: accountName, serverAddress: url.absoluteString, username: username)
                    newAccount = account
                    try KeychainStore().save(password, for: account.passwordKey)
                    modelContext.insert(account)
                }
                try modelContext.save()
                dismiss()
            } catch {
                if let newAccount { try? KeychainStore().delete(newAccount.passwordKey) }
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func effectivePassword() throws -> String {
        if !password.isEmpty { return password }
        if let account, let savedPassword = try KeychainStore().value(for: account.passwordKey), !savedPassword.isEmpty {
            return savedPassword
        }
        throw WebDAVAccountInputError.missingCredentials
    }
}
