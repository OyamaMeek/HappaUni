import SwiftUI
import WebKit

struct EPUBReaderView: View {
    let url: URL

    @State private var book: EPUBBook?
    @State private var selectedChapter = 0
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("无法打开 EPUB", systemImage: "book.closed", description: Text(errorMessage))
            } else if let book, book.chapters.indices.contains(selectedChapter) {
                EPUBChapterWebView(
                    chapter: book.chapters[selectedChapter],
                    contentURL: book.contentURL,
                    errorMessage: $errorMessage
                )
                .background(Color.black)
                .safeAreaInset(edge: .bottom) {
                    readerCapsule(for: book)
                }
            } else {
                ProgressView("正在解压 EPUB…")
            }
        }
        .task(id: url) {
            do {
                book = try EPUBService.open(url)
                selectedChapter = 0
                errorMessage = nil
            } catch {
                book = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func readerCapsule(for book: EPUBBook) -> some View {
        HStack(spacing: 14) {
            Button { selectedChapter = max(0, selectedChapter - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(selectedChapter == 0)
            Menu {
                Picker("章节", selection: $selectedChapter) {
                    ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                        Text(chapter.title).tag(index)
                    }
                }
            } label: {
                Text(book.chapters[selectedChapter].title)
                    .lineLimit(1)
                    .frame(maxWidth: 180)
            }
            Button { selectedChapter = min(book.chapters.count - 1, selectedChapter + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(selectedChapter >= book.chapters.count - 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

private struct EPUBChapterWebView: UIViewRepresentable {
    let chapter: EPUBChapter
    let contentURL: URL
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator { Coordinator(errorMessage: $errorMessage) }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != chapter.url else { return }
        context.coordinator.loadedURL = chapter.url
        view.loadFileURL(chapter.url, allowingReadAccessTo: contentURL)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding private var errorMessage: String?
        var loadedURL: URL?

        init(errorMessage: Binding<String?>) {
            _errorMessage = errorMessage
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            errorMessage = "无法显示 EPUB 章节：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            errorMessage = "无法显示 EPUB 章节：\(error.localizedDescription)"
        }
    }
}
