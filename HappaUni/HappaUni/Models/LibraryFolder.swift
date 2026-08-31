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
        func nodes(parentID: UUID?, ancestors: Set<UUID>) -> [FolderTreeNode] {
            (grouped[parentID] ?? [])
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .compactMap { folder in
                    guard !ancestors.contains(folder.id) else { return nil }
                    return FolderTreeNode(
                        folder: folder,
                        children: nodes(parentID: folder.id, ancestors: ancestors.union([folder.id]))
                    )
                }
        }
        return nodes(parentID: nil, ancestors: [])
    }

    static func descendantIDs(of rootID: UUID, in folders: [LibraryFolder]) -> Set<UUID> {
        let children = Dictionary(grouping: folders, by: \LibraryFolder.parentID)
        var visited: Set<UUID> = []

        func visit(_ id: UUID) {
            guard visited.insert(id).inserted else { return }
            for child in children[id] ?? [] {
                visit(child.id)
            }
        }

        visit(rootID)
        return visited
    }
}
