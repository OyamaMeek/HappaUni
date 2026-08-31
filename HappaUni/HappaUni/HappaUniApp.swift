import SwiftData
import SwiftUI

@main
struct HappaUniApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: LibraryDocument.self,
                LibraryFolder.self,
                WebDAVAccount.self,
                AIConversation.self,
                AIConversationMessage.self
            )
        } catch {
            fatalError("无法初始化本地资料库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
