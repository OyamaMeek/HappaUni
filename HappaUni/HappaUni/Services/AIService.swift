import Foundation
import PDFKit

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

enum AISettings {
    static let systemPromptKey = "ai.systemPrompt"

    static func documentAssistantPrompt(
        customPrompt: String,
        documentName: String,
        documentContent: String
    ) -> String {
        let instructions = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseInstructions = instructions.isEmpty
            ? "你是 HappaUni 的文档助手。请用中文回答，并严格依据下列文档内容；不确定时说明不确定。"
            : instructions
        return """
        \(baseInstructions)

        回答中的数学公式请使用 LaTex：行内公式使用 \\( ... \\)，独立公式使用 \\[ ... \\]；可使用 aligned、matrix、cases、equation 等环境。不要把公式放进 Markdown 代码块。

        文档：\(documentName)

        内容：
        \(documentContent)
        """
    }
}

enum AIContextExtractor {
    static func truncate(_ text: String, maximumCharacters: Int = 12_000) -> String {
        guard maximumCharacters > 0, text.count > maximumCharacters else { return text }
        return "…" + String(text.suffix(maximumCharacters))
    }

    static func text(for document: LibraryDocument) -> String {
        switch document.type {
        case .markdown, .text, .tex:
            guard let content = try? String(contentsOf: document.url, encoding: .utf8) else { return "" }
            return truncate(content)
        case .pdf:
            guard let pdf = PDFDocument(url: document.url) else { return "" }
            let content = (0..<pdf.pageCount)
                .compactMap { pdf.page(at: $0)?.string }
                .joined(separator: "\n\n")
            return truncate(content)
        default:
            return ""
        }
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

    func stream(
        messages: [AIMessage],
        configuration: AIConfiguration
    ) -> AsyncThrowingStream<String, Swift.Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard !configuration.apiKey.isEmpty else { throw Error.missingAPIKey }
                    let endpoint = configuration.baseURL.appendingPathComponent("chat/completions")
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.httpBody = try JSONEncoder().encode(
                        Request(
                            model: configuration.model,
                            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                            stream: true
                        )
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        throw Error.requestFailed
                    }

                    for try await line in bytes.lines where line.hasPrefix("data:") {
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        let chunk = try JSONDecoder().decode(StreamResponse.self, from: data)
                        if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private struct Request: Codable {
        let model: String
        let messages: [RequestMessage]
        var stream: Bool?
    }
    private struct RequestMessage: Codable { let role: String; let content: String }
    private struct Response: Codable { let choices: [Choice]; struct Choice: Codable { let message: RequestMessage } }
    private struct StreamResponse: Codable {
        let choices: [Choice]
        struct Choice: Codable {
            let delta: Delta
        }
        struct Delta: Codable {
            let content: String?
        }
    }
    enum Error: LocalizedError { case missingAPIKey, requestFailed
        var errorDescription: String? { self == .missingAPIKey ? "请先在设置中配置 API Key。" : "AI 服务请求失败。" }
    }
}
