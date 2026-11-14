import Foundation

/// Plain HTTPS fetches, with a timeout and no cookies.
public struct Web: Sendable {
    public enum Failure: Error { case status(Int) }

    /// Basketball-Reference turns away clients that do not look like a browser.
    static let browser = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:140.0) Gecko/20100101 Firefox/140.0"

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    public func data(_ url: URL, timeout: TimeInterval = 12, browser: Bool = false) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if browser { request.setValue(Web.browser, forHTTPHeaderField: "User-Agent") }
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.status(http.statusCode)
        }
        return data
    }

    public func json(_ url: URL, timeout: TimeInterval = 12) async throws -> JSON {
        try JSON(data: await data(url, timeout: timeout))
    }

    /// The answer, or nil when it could not be had: for the parts a screen can do without.
    public func optionalJSON(_ url: URL, timeout: TimeInterval = 12) async -> JSON? {
        try? await json(url, timeout: timeout)
    }

    /// A web page, asked for as a browser would.
    public func page(_ url: URL) async -> String? {
        guard let data = try? await data(url, timeout: 20, browser: true) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
