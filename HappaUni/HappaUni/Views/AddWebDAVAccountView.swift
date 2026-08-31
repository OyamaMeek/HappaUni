import SwiftData
import SwiftUI

struct AddWebDAVAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var serverAddress = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var isSaving = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

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
                    SecureField("密码或应用专用密码", text: $password)
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
            .navigationTitle("添加 WebDAV")
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
                try input.validateCredentials()
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
            var account: WebDAVAccount?
            do {
                let accountName = try input.validatedName()
                let url = try input.validatedURL()
                try input.validateCredentials()
                let newAccount = WebDAVAccount(name: accountName, serverAddress: url.absoluteString, username: username)
                account = newAccount
                try KeychainStore().save(password, for: newAccount.passwordKey)
                try await WebDAVService.shared.ensureDirectory(
                    serverURL: url,
                    username: username,
                    password: password,
                    path: WebDAVRemotePath.libraryRoot
                )
                modelContext.insert(newAccount)
                try modelContext.save()
                dismiss()
            } catch {
                if let account { try? KeychainStore().delete(account.passwordKey) }
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
