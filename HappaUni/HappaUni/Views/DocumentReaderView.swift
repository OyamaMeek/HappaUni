import PDFKit
import QuickLook
import SwiftUI
import UIKit

struct DocumentReaderView: View {
    let document: LibraryDocument
    @State private var isShowingAIChat = false

    var body: some View {
        Group {
            switch document.type {
            case .pdf:
                PDFReader(url: document.url)
            case .markdown, .text:
                TextDocumentReader(url: document.url, title: document.name)
            case .image:
                ImageDocumentReader(url: document.url)
            case .epub:
                EPUBReader(url: document.url)
            case .other:
                UnsupportedDocumentView(document: document, message: "此文件类型暂不支持预览。")
            }
        }
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isShowingAIChat = true } label: {
                    Label("AI 问答", systemImage: "sparkles")
                }
            }
        }
        .sheet(isPresented: $isShowingAIChat) {
            AIChatView(document: document)
        }
    }
}

private struct PDFReader: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
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
                    MarkdownText(content: content)
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

private struct MarkdownText: View {
    let content: String

    var body: some View {
        if let markdown = try? AttributedString(markdown: content) {
            Text(markdown)
                .font(.body)
        } else {
            Text(content)
                .font(.body)
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

private struct EPUBReader: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
