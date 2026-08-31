import SwiftUI
import WebKit

struct MarkdownReaderView: View {
    let url: URL

    @State private var content = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let errorMessage {
                ContentUnavailableView("无法读取 Markdown", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                MarkdownWebView(html: MarkdownHTML.document(for: content))
                    .background(Color.black)
            }
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

private struct MarkdownWebView: UIViewRepresentable {
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

private enum MarkdownHTML {
    static func document(for source: String) -> String {
        let body = source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let escaped = escape(String(line))
                if escaped.hasPrefix("### ") { return "<h3>\(String(escaped.dropFirst(4)))</h3>" }
                if escaped.hasPrefix("## ") { return "<h2>\(String(escaped.dropFirst(3)))</h2>" }
                if escaped.hasPrefix("# ") { return "<h1>\(String(escaped.dropFirst(2)))</h1>" }
                if escaped.hasPrefix("- ") || escaped.hasPrefix("* ") { return "<p>• \(String(escaped.dropFirst(2)))</p>" }
                if escaped.isEmpty { return "<div class=\"gap\"></div>" }
                return "<p>\(escaped)</p>"
            }
            .joined()
        return """
        <!doctype html><html lang="zh-Hans"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>:root{color-scheme:dark}body{margin:0;padding:20px 20px 100px;background:#000;color:#f2f2f7;font:-apple-system-body;line-height:1.6}h1,h2,h3{line-height:1.25}h1{font-size:27px}h2{font-size:22px}h3{font-size:18px}p{margin:0 0 12px}.gap{height:8px}</style>
        </head><body>\(body)</body></html>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
