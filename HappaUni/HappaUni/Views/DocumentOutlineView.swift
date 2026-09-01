import Foundation
import PDFKit
import SwiftUI

struct DocumentOutlineItem: Identifiable, Hashable, Sendable {
    enum Destination: Hashable, Sendable {
        case page(Int)
        case anchor(String)
    }

    let id: String
    let title: String
    let level: Int
    let destination: Destination
}

enum DocumentOutlineExtractor {
    static func items(for document: LibraryDocument) -> [DocumentOutlineItem] {
        items(type: document.type, url: document.url)
    }

    static func items(type: DocumentType, url: URL) -> [DocumentOutlineItem] {
        switch type {
        case .pdf:
            return pdfItems(at: url)
        case .markdown:
            return markdownItems(at: url)
        default:
            return []
        }
    }

    static func markdownItems(source: String) -> [DocumentOutlineItem] {
        source
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { index, line in
                let value = String(line)
                let hashes = value.prefix { $0 == "#" }.count
                guard hashes > 0, hashes <= 6 else { return nil }
                let title = value.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { return nil }
                return DocumentOutlineItem(
                    id: "heading-\(index)",
                    title: title,
                    level: hashes - 1,
                    destination: .anchor("heading-\(index)")
                )
            }
    }

    private static func markdownItems(at url: URL) -> [DocumentOutlineItem] {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return markdownItems(source: source)
    }

    private static func pdfItems(at url: URL) -> [DocumentOutlineItem] {
        guard let document = PDFDocument(url: url) else { return [] }
        var result: [DocumentOutlineItem] = []

        func appendChildren(of outline: PDFOutline, level: Int) {
            for index in 0..<outline.numberOfChildren {
                guard let child = outline.child(at: index) else { continue }
                let page = pageNumber(for: child, in: document)
                let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let title, !title.isEmpty, let page {
                    result.append(
                        DocumentOutlineItem(
                            id: "pdf-outline-\(level)-\(result.count)-\(page)",
                            title: title,
                            level: level,
                            destination: .page(page)
                        )
                    )
                }
                appendChildren(of: child, level: level + 1)
            }
        }

        if let root = document.outlineRoot {
            appendChildren(of: root, level: 0)
        }

        if result.isEmpty {
            result = (0..<document.pageCount).map { index in
                DocumentOutlineItem(
                    id: "pdf-page-\(index)",
                    title: "第 \(index + 1) 页",
                    level: 0,
                    destination: .page(index + 1)
                )
            }
        }
        return result
    }

    private static func pageNumber(for outline: PDFOutline, in document: PDFDocument) -> Int? {
        let destination = outline.destination ?? (outline.action as? PDFActionGoTo)?.destination
        guard let page = destination?.page else { return nil }
        let index = document.index(for: page)
        return index == NSNotFound ? nil : index + 1
    }
}

struct DocumentOutlineView: View {
    let document: LibraryDocument
    let onDestination: (DocumentOutlineItem.Destination) -> Void

    @State private var items: [DocumentOutlineItem] = []
    @State private var selectedID: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet.indent")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("目录")
                        .font(.headline)
                    Text("点按目录跳转")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Divider()

            if items.isEmpty {
                ContentUnavailableView(
                    "暂无目录",
                    systemImage: "list.bullet.rectangle",
                    description: Text("此文件没有可识别的章节。")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(items, selection: $selectedID) { item in
                    Button {
                        selectedID = item.id
                        onDestination(item.destination)
                    } label: {
                        HStack(spacing: 8) {
                            if item.level > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(item.title)
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if case let .page(page) = item.destination {
                                Text("\(page)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, CGFloat(item.level) * 14)
                    }
                    .buttonStyle(.plain)
                    .tag(item.id)
                }
                .listStyle(.plain)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .task(id: document.id) {
            let type = document.type
            let url = document.url
            items = await Task.detached(priority: .userInitiated) {
                DocumentOutlineExtractor.items(type: type, url: url)
            }.value
        }
    }
}
