import Foundation

struct GitHubConfiguration: Codable {
    var clientID: String
    var redirectURI: String
    var repositoryName: String
    static let `default` = GitHubConfiguration(clientID: "", redirectURI: "happauni://oauth", repositoryName: "HappaUni-sync")
}

final class GitHubService {
    static let shared = GitHubService()
    private let keychain = KeychainStore()
    private let tokenKey = "github.accessToken"
    private let usernameKey = "github.username"

    var isAuthenticated: Bool { (try? keychain.value(for: tokenKey)) != nil }
    var username: String? { try? keychain.value(for: usernameKey) }

    func saveAccessToken(_ token: String) async throws {
        try keychain.save(token, for: tokenKey)
        let user = try await currentUser()
        try keychain.save(user.login, for: usernameKey)
    }

    func signOut() throws { try keychain.delete(tokenKey); try keychain.delete(usernameKey) }

    func ensureRepository(named name: String) async throws {
        let endpoint = URL(string: "https://api.github.com/user/repos")!
        var request = try authenticatedRequest(url: endpoint, method: "POST")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": name, "private": true, "auto_init": true])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 422 else { throw Error.requestFailed }
    }

    func commit(data: Data, repository: String, path: String, message: String) async throws -> String {
        guard let owner = username else { throw Error.notAuthenticated }
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/contents/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)")!
        var request = try authenticatedRequest(url: endpoint, method: "PUT")
        var body: [String: Any] = ["message": message, "content": data.base64EncodedString()]
        if let sha = try? await fileSHA(repository: repository, path: path) { body["sha"] = sha }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.requestFailed }
        return try JSONDecoder().decode(CommitResponse.self, from: data).commit.sha
    }

    func listSyncedDocuments(repository: String) async throws -> [GitHubRepositoryItem] {
        let folders = try await listContents(repository: repository, path: "documents")
        var files: [GitHubRepositoryItem] = []
        for folder in folders where folder.type == "dir" {
            files += try await listContents(repository: repository, path: folder.path).filter { $0.type == "file" }
        }
        return files
    }

    func download(repository: String, path: String) async throws -> Data {
        guard let owner = username else { throw Error.notAuthenticated }
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/contents/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)")!
        let request = try authenticatedRequest(url: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.requestFailed }
        let file = try JSONDecoder().decode(ContentFile.self, from: data)
        guard let encoded = file.content,
              let content = Data(base64Encoded: encoded.replacingOccurrences(of: "\n", with: "")) else { throw Error.invalidResponse }
        return content
    }

    private func currentUser() async throws -> User {
        let request = try authenticatedRequest(url: URL(string: "https://api.github.com/user")!)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.requestFailed }
        return try JSONDecoder().decode(User.self, from: data)
    }

    private func listContents(repository: String, path: String) async throws -> [GitHubRepositoryItem] {
        guard let owner = username else { throw Error.notAuthenticated }
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/contents/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)")!
        let request = try authenticatedRequest(url: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.requestFailed }
        return try JSONDecoder().decode([GitHubRepositoryItem].self, from: data)
    }

    private func fileSHA(repository: String, path: String) async throws -> String {
        guard let owner = username else { throw Error.notAuthenticated }
        let endpoint = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/contents/\(path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)")!
        let request = try authenticatedRequest(url: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.requestFailed }
        return try JSONDecoder().decode(ContentFile.self, from: data).sha
    }

    private func authenticatedRequest(url: URL, method: String = "GET") throws -> URLRequest {
        guard let token = try keychain.value(for: tokenKey) else { throw Error.notAuthenticated }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private struct User: Codable { let login: String }
    private struct ContentFile: Codable { let sha: String; let content: String? }
    struct GitHubRepositoryItem: Codable, Equatable {
        let name: String
        let path: String
        let sha: String
        let type: String
    }
    private struct CommitResponse: Codable { let commit: Commit; struct Commit: Codable { let sha: String } }
    enum Error: LocalizedError { case notAuthenticated, requestFailed, invalidResponse
        var errorDescription: String? { "GitHub 同步请求失败，请检查登录状态和网络。" }
    }
}
