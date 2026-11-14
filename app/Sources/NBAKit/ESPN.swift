import Foundation

/// ESPN's public API: no key, no account.
public struct ESPN: Sendable {
    public enum Failure: Error { case status(Int) }

    static let site = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"

    /// With no day ESPN answers for "today", which is also how the current day and the season calendar are found.
    public static func scoreboardURL(day: String? = nil) -> URL {
        URL(string: day.map { "\(site)/scoreboard?dates=\($0)" } ?? "\(site)/scoreboard")!
    }

    public static func summaryURL(game: String) -> URL {
        URL(string: "\(site)/summary?event=\(game)")!
    }

    /// `season`: the year it ends; nil for the current one.
    public static func standingsURL(season: Int? = nil) -> URL {
        let base = "https://site.api.espn.com/apis/v2/sports/basketball/nba/standings?seasontype=2"
        return URL(string: season.map { "\(base)&season=\($0)" } ?? base)!
    }

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    public func json(_ url: URL) async throws -> JSON {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.status(http.statusCode)
        }
        return try JSON(data: data)
    }

    public func scoreboard(day: String? = nil) async throws -> Scoreboard {
        Scoreboard(try await json(ESPN.scoreboardURL(day: day)))
    }

    public func boxScore(game: String) async throws -> BoxScore {
        BoxScore(try await json(ESPN.summaryURL(game: game)))
    }

    public func standings(season: Int? = nil) async throws -> Standings {
        Standings(try await json(ESPN.standingsURL(season: season)))
    }
}
