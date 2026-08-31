import Foundation

struct AIMessage: Codable, Identifiable, Equatable {
    enum Role: String, Codable { case system, user, assistant }
    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id; self.role = role; self.content = content; self.createdAt = createdAt
    }
}

struct AIConfiguration: Codable, Equatable {
    var apiKey: String
    var baseURL: URL
    var model: String
    static let `default` = AIConfiguration(apiKey: "", baseURL: URL(string: "https://api.openai.com/v1")!, model: "gpt-4o-mini")
}

enum AIContextExtractor {
    static func truncate(_ text: String, maximumCharacters: Int = 12_000) -> String {
        guard maximumCharacters > 0, text.count > maximumCharacters else { return text }
        return "…" + String(text.suffix(maximumCharacters))
    }

    static func text(for document: LibraryDocument) -> String {
        guard document.type == .markdown || document.type == .text,
              let content = try? String(contentsOf: document.url, encoding: .utf8) else { return "" }
        return truncate(content)
    }
}

final class AIService {
    static let shared = AIService()

    func complete(messages: [AIMessage], configuration: AIConfiguration) async throws -> String {
        guard !configuration.apiKey.isEmpty else { throw Error.missingAPIKey }
        let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Request(model: configuration.model, messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) }))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw Error.requestFailed }
        return try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content ?? ""
    }

    private struct Request: Codable { let model: String; let messages: [RequestMessage] }
    private struct RequestMessage: Codable { let role: String; let content: String }
    private struct Response: Codable { let choices: [Choice]; struct Choice: Codable { let message: RequestMessage } }
    enum Error: LocalizedError { case missingAPIKey, requestFailed
        var errorDescription: String? { self == .missingAPIKey ? "请先在设置中配置 API Key。" : "AI 服务请求失败。" }
    }
}
