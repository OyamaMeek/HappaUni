import SwiftUI

struct KnowledgeMapNode: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var children: [KnowledgeMapNode] = []
}

enum KnowledgeMapParser {
    static func parse(_ response: String, fallbackTitle: String) -> KnowledgeMapNode {
        let parsed = response
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { raw -> (level: Int, title: String)? in
                let line = String(raw)
                let spaces = line.prefix { $0 == " " || $0 == "\t" }
                var title = line.trimmingCharacters(in: .whitespaces)
                while title.hasPrefix("#") || title.hasPrefix("-") || title.hasPrefix("*") || title.hasPrefix("•") {
                    title.removeFirst()
                    title = title.trimmingCharacters(in: .whitespaces)
                }
                guard !title.isEmpty else { return nil }
                return (spaces.count / 2, title)
            }
        guard let first = parsed.first else { return KnowledgeMapNode(title: fallbackTitle) }
        return build(parsed, at: 0, level: first.level).node
    }

    private static func build(_ values: [(level: Int, title: String)], at start: Int, level: Int) -> (node: KnowledgeMapNode, next: Int) {
        var node = KnowledgeMapNode(title: values[start].title)
        var index = start + 1
        while index < values.count {
            if values[index].level <= level { break }
            let child = build(values, at: index, level: values[index].level)
            node.children.append(child.node)
            index = child.next
        }
        return (node, index)
    }
}

struct KnowledgeMapView: View {
    let document: LibraryDocument

    @AppStorage("ai.baseURL") private var baseURLString = "https://api.openai.com/v1"
    @AppStorage("ai.model") private var model = "gpt-4o-mini"
    @State private var map: KnowledgeMapNode?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let map {
                ScrollView([.horizontal, .vertical]) {
                    MindMapNodeView(node: map, emphasized: true)
                        .padding(36)
                        .frame(minWidth: 620, minHeight: 440, alignment: .center)
                }
                .background(Color(uiColor: .systemBackground))
            } else if isGenerating {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("正在提炼 PDF 的知识结构…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView {
                    Label("知识地图", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("将当前 PDF 提交给已配置的 AI，生成可展开阅读的思维导图。")
                } actions: {
                    Button("生成知识地图", systemImage: "sparkles", action: generate)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("知识地图")
        .alert("知识地图", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("确定", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .toolbar {
            if map != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重新生成", systemImage: "arrow.clockwise", action: generate)
                        .disabled(isGenerating)
                }
            }
        }
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        Task {
            do {
                let apiKey = try KeychainStore().value(for: "openai.apiKey") ?? ""
                guard let baseURL = URL(string: baseURLString) else { throw AIService.Error.requestFailed }
                let context = AIContextExtractor.text(for: document)
                guard !context.isEmpty else { throw KnowledgeMapError.noExtractableText }
                let prompt = """
                请根据下面 PDF 的内容生成中文知识地图。只返回纯文本层级大纲：第一行是中心主题；每一层子节点使用两个空格缩进，并以 - 开头。保留关键概念、论点、方法和结论，最多四层，每层简洁。

                文件：\(document.name)

                内容：
                \(context)
                """
                let configuration = AIConfiguration(apiKey: apiKey, baseURL: baseURL, model: model)
                let response = try await AIService.shared.complete(
                    messages: [AIMessage(role: .user, content: prompt)],
                    configuration: configuration
                )
                map = KnowledgeMapParser.parse(response, fallbackTitle: document.name)
            } catch {
                errorMessage = error.localizedDescription
            }
            isGenerating = false
        }
    }
}

private enum KnowledgeMapError: LocalizedError {
    case noExtractableText

    var errorDescription: String? { "这份 PDF 中没有可提取的文本。" }
}

private struct MindMapNodeView: View {
    let node: KnowledgeMapNode
    var emphasized = false

    var body: some View {
        VStack(spacing: 14) {
            Text(node.title)
                .font(emphasized ? .headline : .subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(minWidth: emphasized ? 170 : 130, maxWidth: 220)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(emphasized ? Color.accentColor : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(emphasized ? .white : .primary)

            if !node.children.isEmpty {
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: 1, height: 18)
                HStack(alignment: .top, spacing: 18) {
                    ForEach(node.children) { child in
                        MindMapNodeView(node: child)
                    }
                }
            }
        }
    }
}
