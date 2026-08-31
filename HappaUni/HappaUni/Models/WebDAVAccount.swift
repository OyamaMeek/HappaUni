import Foundation
import SwiftData

struct WebDAVAccountInput: Equatable {
    var name: String
    var serverAddress: String
    var username: String
    var password: String

    func validatedName() throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WebDAVAccountInputError.missingName }
        return value
    }

    func validatedURL() throws -> URL {
        let value = serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw WebDAVAccountInputError.invalidURL }
        let address = value.contains("://") ? value : "https://\(value)"
        guard let url = URL(string: address), url.scheme == "https", url.host != nil else {
            throw WebDAVAccountInputError.invalidURL
        }
        return url
    }

    func validateCredentials(with password: String? = nil) throws {
        guard !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !(password ?? self.password).isEmpty else {
            throw WebDAVAccountInputError.missingCredentials
        }
    }
}

enum WebDAVAccountInputError: LocalizedError {
    case missingName
    case invalidURL
    case missingCredentials

    var errorDescription: String? {
        switch self {
        case .missingName: "请输入服务器名称。"
        case .invalidURL: "请输入有效的 WebDAV 服务器地址。"
        case .missingCredentials: "请输入用户名和密码。"
        }
    }
}

@Model
final class WebDAVAccount {
    @Attribute(.unique) var id: UUID
    var name: String
    var serverAddress: String
    var username: String
    var createdAt: Date
    var lastSyncedAt: Date?

    init(id: UUID = UUID(), name: String, serverAddress: String, username: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.serverAddress = serverAddress
        self.username = username
        self.createdAt = createdAt
    }

    var serverURL: URL? { URL(string: serverAddress) }
    var passwordKey: String { "webdav.password.\(id.uuidString)" }
}
