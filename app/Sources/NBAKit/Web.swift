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

    public func data(_ url: URL, timeout: TimeInterval = 12, browser: Bool = false, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        if browser { request.setValue(Web.browser, forHTTPHeaderField: "User-Agent") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
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

    /// The scoreboards of many days, a few at a time. A day that could not be had is left out.
    public func scoreboards(_ days: [String]) async -> [String: JSON] {
        var boards: [String: JSON] = [:]
        var rest = days[...]
        while !rest.isEmpty {
            let batch = rest.prefix(8)
            rest = rest.dropFirst(8)
            await withTaskGroup(of: (String, JSON?).self) { group in
                for day in batch {
                    group.addTask { (day, await optionalJSON(ESPN.scoreboardURL(day: day), timeout: 10)) }
                }
                for await (day, board) in group { boards[day] = board }
            }
        }
        return boards
    }

    /// NBA.com's stats API, which stalls or refuses clients that do not look like its own site.
    public func nbaStats(_ url: URL) async -> JSON? {
        let headers = [
            "Referer": "https://www.nba.com/", "Origin": "https://www.nba.com",
            "Accept": "application/json, text/plain, */*", "Accept-Language": "en-US,en;q=0.9",
            "x-nba-stats-origin": "stats", "x-nba-stats-token": "true",
        ]
        guard let data = try? await data(url, timeout: 8, browser: true, headers: headers) else { return nil }
        return try? JSON(data: data)
    }

    /// A web page and its HTTP status (0 when the site could not be reached), asked for as a browser would.
    public func pageWithStatus(_ url: URL) async -> (html: String, status: Int) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Web.browser, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return ("", 0) }
        return (String(decoding: data, as: UTF8.self), (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    /// A web page, asked for as a browser would.
    public func page(_ url: URL) async -> String? {
        guard let data = try? await data(url, timeout: 20, browser: true) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
