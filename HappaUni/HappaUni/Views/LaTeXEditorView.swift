import SwiftUI
import WebKit

struct LaTeXEditorView: View {
    let url: URL

    @State private var source = ""
    @State private var isPreviewing = false
    @State private var errorMessage: String?
    @State private var saveMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("无法读取 LaTeX", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if isPreviewing {
                LaTeXPreviewWebView(html: LaTeXService.html(for: source))
                    .background(Color.black)
            } else {
                TextEditor(text: $source)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .background(Color.black)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 14) {
                Button {
                    do {
                        try LaTeXService.save(source, to: url)
                        saveMessage = "已保存"
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                } label: {
                    Label("保存", systemImage: "square.and.arrow.down")
                }

                Button {
                    isPreviewing.toggle()
                } label: {
                    Label(isPreviewing ? "编辑" : "预览", systemImage: isPreviewing ? "text.cursor" : "doc.text.magnifyingglass")
                }

                if let saveMessage {
                    Text(saveMessage).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .task(id: url) {
            do {
                source = try String(contentsOf: url, encoding: .utf8)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct LaTeXPreviewWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var html = ""
    }
}
