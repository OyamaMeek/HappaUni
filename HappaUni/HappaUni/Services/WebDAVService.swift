import Foundation

struct WebDAVFile: Identifiable, Equatable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedAt: Date?
    let eTag: String?
    var id: String { path }
}

final class WebDAVXMLParser: NSObject, XMLParserDelegate {
    private var files: [WebDAVFile] = []
    private var basePath = "/"
    private var currentElement = ""
    private var currentValues: [String: String] = [:]
    private var isCollection = false

    func parse(data: Data, basePath: String) throws -> [WebDAVFile] {
        self.basePath = basePath.hasSuffix("/") ? basePath : basePath + "/"
        files = []
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else { throw parser.parserError ?? WebDAVService.Error.invalidResponse }
        return files
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName.lowercased()
        if currentElement == "response" { currentValues = [:]; isCollection = false }
        if currentElement == "collection" { isCollection = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard ["href", "displayname", "getcontentlength", "getlastmodified", "getetag"].contains(currentElement) else { return }
        currentValues[currentElement, default: ""] += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName.lowercased() == "response", let href = currentValues["href"]?.removingPercentEncoding else { return }
        let normalized = href.hasPrefix("/") ? href : "/" + href
        let comparablePath = normalized.hasSuffix("/") ? normalized : normalized + "/"
        guard comparablePath != basePath else { return }
        let filename = currentValues["displayname"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (filename?.isEmpty == false ? filename! : URL(fileURLWithPath: normalized).lastPathComponent)
        let size = Int64(currentValues["getcontentlength"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0") ?? 0
        let date = currentValues["getlastmodified"].flatMap { Self.httpDateFormatter.date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        files.append(WebDAVFile(path: normalized, name: name, isDirectory: isCollection, size: size, modifiedAt: date, eTag: currentValues["getetag"]?.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

final class WebDAVService {
    static let shared = WebDAVService()
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func testConnection(url: URL, username: String, password: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("0", forHTTPHeaderField: "Depth")
        request.setBasicAuthorization(username: username, password: password)
        let (_, response) = try await session.data(for: request)
        try validate(response, otherwise: .connectionFailed)
    }

    func listDirectory(url: URL, username: String, password: String, path: String = "/") async throws -> [WebDAVFile] {
        var request = URLRequest(url: WebDAVRemotePath.url(serverURL: url, path: path))
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
        request.setBasicAuthorization(username: username, password: password)
        request.httpBody = Data("<D:propfind xmlns:D=\"DAV:\"><D:prop><D:displayname/><D:getcontentlength/><D:getlastmodified/><D:getetag/><D:resourcetype/></D:prop></D:propfind>".utf8)
        let (data, response) = try await session.data(for: request)
        try validate(response, otherwise: .listDirectoryFailed)
        return try WebDAVXMLParser().parse(data: data, basePath: path)
    }

    func download(url: URL, username: String, password: String, to localURL: URL) async throws {
        var request = URLRequest(url: url)
        request.setBasicAuthorization(username: username, password: password)
        let (temporaryURL, response) = try await session.download(for: request)
        try validate(response, otherwise: .downloadFailed)
        try? FileManager.default.removeItem(at: localURL)
        try FileManager.default.moveItem(at: temporaryURL, to: localURL)
    }

    func upload(data: Data, to url: URL, username: String, password: String, eTag: String? = nil) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setBasicAuthorization(username: username, password: password)
        if let eTag { request.setValue(eTag, forHTTPHeaderField: "If-Match") }
        let (_, response) = try await session.upload(for: request, from: data)
        try validate(response, otherwise: .uploadFailed)
    }

    enum Error: LocalizedError { case invalidResponse, connectionFailed, listDirectoryFailed, downloadFailed, uploadFailed
        var errorDescription: String? { "WebDAV 请求失败，请检查服务器地址和账户信息。" }
    }

    private func validate(_ response: URLResponse, otherwise error: Error) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 207 else { throw error }
    }
}

private extension URLRequest {
    mutating func setBasicAuthorization(username: String, password: String) {
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    }
}

enum WebDAVRemotePath {
    static func join(base: String, child: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedChild = child.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = [trimmedBase, trimmedChild].filter { !$0.isEmpty }
        return "/" + components.joined(separator: "/")
    }

    static func url(serverURL: URL, path: String) -> URL {
        serverURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
}
