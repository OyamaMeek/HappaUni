import Foundation
import SwiftData

@Model
final class LibraryFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    var parentID: UUID?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}

struct FolderTreeNode: Identifiable {
    let folder: LibraryFolder
    let children: [FolderTreeNode]
    var id: UUID { folder.id }
    var optionalChildren: [FolderTreeNode]? { children.isEmpty ? nil : children }
}

enum FolderTreeBuilder {
    static func make(from folders: [LibraryFolder]) -> [FolderTreeNode] {
        let grouped = Dictionary(grouping: folders, by: \LibraryFolder.parentID)
        func nodes(parentID: UUID?) -> [FolderTreeNode] {
            (grouped[parentID] ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { FolderTreeNode(folder: $0, children: nodes(parentID: $0.id)) }
        }
        return nodes(parentID: nil)
    }
}
