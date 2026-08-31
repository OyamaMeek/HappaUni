import SwiftUI

struct AIChatView: View {
    let document: LibraryDocument

    @Environment(\.dismiss) private var dismiss
    @AppStorage("ai.baseURL") private var baseURLString = "https://api.openai.com/v1"
    @AppStorage("ai.model") private var model = "gpt-4o-mini"
    @State private var messages: [AIMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    ContentUnavailableView {
                        Label("询问文档", systemImage: "sparkles")
                    } description: {
                        Text("提出问题，AI 会结合当前文档内容回答。")
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(messages.filter { $0.role != .system }) { message in
                                    MessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                            .padding()
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let lastID = messages.last(where: { $0.role != .system })?.id {
                                withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                            }
                        }
                    }
                }

                Divider()
                HStack(alignment: .bottom, spacing: 12) {
                    TextField("问问这份文档", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .textFieldStyle(.roundedBorder)
                    Button(action: send) {
                        if isSending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    }
                    .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()
            }
            .navigationTitle("AI 问答")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert("AI 问答", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        draft = ""
        messages.append(AIMessage(role: .user, content: question))
        isSending = true

        Task {
            do {
                let apiKey = try KeychainStore().value(for: "openai.apiKey") ?? ""
                guard let baseURL = URL(string: baseURLString) else { throw AIService.Error.requestFailed }
                var requestMessages = [AIMessage(role: .system, content: systemPrompt)]
                requestMessages.append(contentsOf: messages.filter { $0.role != .system })
                let answer = try await AIService.shared.complete(
                    messages: requestMessages,
                    configuration: AIConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
                )
                messages.append(AIMessage(role: .assistant, content: answer))
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private var systemPrompt: String {
        let context = AIContextExtractor.text(for: document)
        let source = context.isEmpty ? "当前文件不含可直接提取的纯文本，请基于用户的问题说明可做的操作。" : context
        return "你是 HappaUni 的文档助手。请用中文回答，并严格依据下列文档内容；不确定时说明不确定。\n\n文档：\(document.name)\n\n内容：\n\(source)"
    }
}

private struct MessageBubble: View {
    let message: AIMessage

    var body: some View {
        HStack {
            if message.role == .assistant {
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 44)
            } else {
                Spacer(minLength: 44)
                Text(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(.blue, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
