import Foundation
import SwiftData

public enum DocumentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case pdf
    case markdown
    case tex
    case epub
    case image
    case text
    case other

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .markdown: "Markdown"
        case .tex: "TeX"
        case .epub: "EPUB"
        case .image: "图片"
        case .text: "文本"
        case .other: "其他"
        }
    }

    var iconName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .markdown: "text.document"
        case .tex: "function"
        case .epub: "books.vertical"
        case .image: "photo"
        case .text: "doc.text"
        case .other: "doc"
        }
    }

    static func detect(from filename: String) -> DocumentType {
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": .pdf
        case "md", "markdown": .markdown
        case "tex": .tex
        case "epub": .epub
        case "txt", "rtf": .text
        case "jpg", "jpeg", "png", "gif", "heic", "webp": .image
        default: .other
        }
    }
}

@Model
final class LibraryDocument {
    @Attribute(.unique) var id: UUID
    var name: String
    var path: String
    var typeRawValue: String
    var size: Int64
    var createdAt: Date
    var modifiedAt: Date
    var isSyncedToGitHub: Bool
    var gitCommitHash: String?
    var gitLastSyncAt: Date?
    var isFavorite: Bool
    var isArchived: Bool = false
    var tagsRawValue: String
    var folderID: UUID?
    var lastReadPage: Int = 1

    init(
        id: UUID = UUID(),
        name: String,
        url: URL,
        type: DocumentType? = nil,
        size: Int64,
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        isSyncedToGitHub: Bool = false,
        isFavorite: Bool = false,
        isArchived: Bool = false,
        tags: [String] = [],
        folderID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.path = url.path
        self.typeRawValue = (type ?? DocumentType.detect(from: name)).rawValue
        self.size = size
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.isSyncedToGitHub = isSyncedToGitHub
        self.isFavorite = isFavorite
        self.isArchived = isArchived
        self.tagsRawValue = Self.normalizedTags(tags).joined(separator: "\u{1F}")
        self.folderID = folderID
    }

    /// Resolves legacy absolute paths after a reinstall or an app-container change.
    /// Imported files are now kept directly in the app's Documents directory.
    var url: URL {
        let persistedURL = URL(fileURLWithPath: path)
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: persistedURL.path),
              let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        else {
            return persistedURL
        }

        let currentLocation = documentsDirectory.appendingPathComponent(persistedURL.lastPathComponent)
        if fileManager.fileExists(atPath: currentLocation.path) {
            return currentLocation
        }

        // Keep older installs readable until ContentView migrates the file.
        let legacyLocation = documentsDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(persistedURL.lastPathComponent)
        return fileManager.fileExists(atPath: legacyLocation.path) ? legacyLocation : persistedURL
    }
    var tags: [String] {
        get { tagsRawValue.split(separator: "\u{1F}").map(String.init) }
        set { tagsRawValue = Self.normalizedTags(newValue).joined(separator: "\u{1F}") }
    }
    var type: DocumentType { DocumentType(rawValue: typeRawValue) ?? .other }
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private static func normalizedTags(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty && !result.contains(normalized) { result.append(normalized) }
        }
    }
}
