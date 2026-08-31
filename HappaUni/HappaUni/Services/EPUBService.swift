import Foundation

struct EPUBBook: Identifiable, Equatable {
    let url: URL
    let title: String
    var id: URL { url }
}

enum EPUBService {
    static func open(_ url: URL) throws -> EPUBBook {
        guard url.pathExtension.lowercased() == "epub" else { throw Error.invalidFile }
        return EPUBBook(url: url, title: url.deletingPathExtension().lastPathComponent)
    }

    enum Error: LocalizedError { case invalidFile
        var errorDescription: String? { "请选择 EPUB 文件。" }
    }
}
