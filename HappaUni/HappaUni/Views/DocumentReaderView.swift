import SwiftUI
import UIKit

struct DocumentReaderView: View {
    enum RightPanel: String, CaseIterable, Identifiable {
        case chat = "AI 问答"
        case knowledgeMap = "知识地图"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .chat: "sparkles"
            case .knowledgeMap: "point.3.connected.trianglepath.dotted"
            }
        }
    }

    let document: LibraryDocument
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var requestedPDFPage: Int?
    @State private var requestedMarkdownAnchor: String?
    @State private var isOutlineVisible = true
    @State private var isInspectorVisible = true
    @State private var rightPanel: RightPanel = .chat

    private var supportsOutline: Bool {
        document.type == .pdf || document.type == .markdown
    }

    private var supportsKnowledgeMap: Bool { document.type == .pdf }
    private var usesSidebars: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 0) {
            if supportsOutline && usesSidebars && isOutlineVisible {
                DocumentOutlineView(document: document, onDestination: open)
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 340)
                Divider()
            }

            reader
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if usesSidebars && isInspectorVisible {
                Divider()
                inspector
                    .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
            }
        }
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if supportsOutline {
                    Button {
                        isOutlineVisible.toggle()
                    } label: {
                        Label("目录", systemImage: "list.bullet.indent")
                    }
                }

                if supportsKnowledgeMap {
                    Button {
                        rightPanel = .knowledgeMap
                        isInspectorVisible = true
                    } label: {
                        Label("知识地图", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                }

                Button {
                    rightPanel = .chat
                    isInspectorVisible.toggle()
                } label: {
                    Label("AI 问答", systemImage: "sparkles")
                }
            }
        }
    }

    @ViewBuilder
    private var reader: some View {
        switch document.type {
        case .pdf:
            PDFReaderView(url: document.url, requestedPage: $requestedPDFPage)
        case .markdown:
            MarkdownReaderView(url: document.url, requestedAnchor: $requestedMarkdownAnchor)
        case .tex:
            LaTeXEditorView(url: document.url)
        case .text:
            TextDocumentReader(url: document.url, title: document.name)
        case .image:
            ImageDocumentReader(url: document.url)
        case .epub:
            EPUBReaderView(url: document.url)
        case .other:
            UnsupportedDocumentView(document: document, message: "此文件类型暂不支持预览。")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        VStack(spacing: 0) {
            Picker("右侧栏", selection: $rightPanel) {
                Text("AI 问答").tag(RightPanel.chat)
                if supportsKnowledgeMap {
                    Text("知识地图").tag(RightPanel.knowledgeMap)
                }
            }
            .pickerStyle(.segmented)
            .padding(12)

            Divider()

            switch rightPanel {
            case .chat:
                AIChatView(document: document)
            case .knowledgeMap:
                KnowledgeMapView(document: document)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func open(_ destination: DocumentOutlineItem.Destination) {
        switch destination {
        case let .page(page):
            requestedPDFPage = page
        case let .anchor(anchor):
            requestedMarkdownAnchor = anchor
        }
    }
}

private struct TextDocumentReader: View {
    let url: URL
    let title: String
    @State private var content = ""
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                if let errorMessage {
                    ContentUnavailableView("无法读取文件", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    Text(content)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .task(id: url) {
            do {
                content = try String(contentsOf: url, encoding: .utf8)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ImageDocumentReader: View {
    let url: URL

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                ContentUnavailableView("无法加载图片", systemImage: "photo")
            }
        }
    }
}

private struct UnsupportedDocumentView: View {
    let document: LibraryDocument
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(document.type.displayName, systemImage: document.type.iconName)
        } description: {
            Text(message)
        }
    }
}
