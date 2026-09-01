import SwiftUI
import WebKit

struct AIResponseMathView: View {
    let content: String
    @State private var height: CGFloat = 24

    var body: some View {
        AIResponseMathWebView(content: content, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AIResponseMathWebView: UIViewRepresentable {
    let content: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "contentHeight")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content
        webView.loadHTMLString(AIMathRenderer.html(for: content), baseURL: AIMathRenderer.baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastContent = ""
        private let height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name == "contentHeight",
                let value = message.body as? Double
            else {
                return
            }
            height.wrappedValue = max(24, ceil(value))
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}

enum AIMathRenderer {
    static let baseURL = URL(string: "https://cdn.jsdelivr.net/")!

    static func html(for content: String) -> String {
        let escaped = escapeHTML(content)
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <style>
            :root { color-scheme: dark; }
            html, body { margin: 0; padding: 0; background: transparent; color: #f2f2f7; }
            body { font: -apple-system-body; font-size: 17px; line-height: 1.55; overflow-wrap: anywhere; }
            #content { white-space: pre-wrap; }
            mjx-container[jax="CHTML"][display="true"] { margin: 0.8em 0 !important; overflow-x: auto; overflow-y: hidden; }
            mjx-container[jax="CHTML"] { max-width: 100%; }
          </style>
          <script>
            window.MathJax = {
              loader: { load: ['[tex]/ams', '[tex]/mathtools', '[tex]/mhchem', '[tex]/newcommand', '[tex]/noerrors', '[tex]/noundefined'] },
              tex: {
                packages: { '[+]': ['ams', 'mathtools', 'mhchem', 'newcommand', 'noerrors', 'noundefined'] },
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                processEscapes: true,
                processEnvironments: true,
                tags: 'ams'
              },
              options: { enableMenu: false },
              startup: { typeset: true }
            };
          </script>
          <script defer src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
        </head>
        <body>
          <main id="content">\(escaped)</main>
          <script>
            const reportHeight = () => {
              window.webkit?.messageHandlers?.contentHeight?.postMessage(
                Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)
              );
            };
            new ResizeObserver(reportHeight).observe(document.body);
            window.addEventListener('load', reportHeight);
          </script>
        </body>
        </html>
        """
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
