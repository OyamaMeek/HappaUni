import Foundation

enum LaTeXService {
    static func html(for source: String) -> String {
        let escaped = escapeHTML(source)
        return """
        <!doctype html>
        <html lang="zh-Hans">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root { color-scheme: dark; }
            body { margin: 0; background: #000; color: #f2f2f7; font: -apple-system-body; }
            pre { margin: 0; padding: 20px; white-space: pre-wrap; overflow-wrap: anywhere; font: 14px/1.55 ui-monospace, SFMono-Regular, Menlo, monospace; }
          </style>
        </head>
        <body><pre>\(escaped)</pre></body>
        </html>
        """
    }

    static func save(_ source: String, to url: URL) throws {
        try source.data(using: .utf8)?.write(to: url, options: .atomic)
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
