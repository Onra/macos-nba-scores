import Foundation

/// A player's team titles: NBA championships and NBA Cups. ESPN's awards are a player's own (MVP, All-NBA…)
/// and leave out the titles his team won. They are found in two steps: who won, and whether the player was
/// on that team then.
public enum Titles {
    /// The first Cup (then the In-Season Tournament) ended 2023-24.
    public static let firstCup = 2024
    /// The December days the Cup final may fall on.
    public static let cupDays = 5...20

    /// Basketball-Reference codes of past champions -> the franchise today. Champions that no longer exist
    /// (Baltimore Bullets, 1948) have none.
    static let franchises = ["PHW": "GSW", "MNL": "LAL", "SYR": "PHI", "STL": "ATL", "WSB": "WAS", "SEA": "OKC", "ROC": "SAC"]

    public struct CupFinal: Codable, Hashable, Sendable {
        public var teamID = ""
        public var date = ""
    }

    /// One game of a player's game log.
    public struct LogGame: Hashable, Sendable {
        public var date = ""
        public var teamID = ""
    }

    /// Season end year -> ESPN team id of the NBA (and BAA) champion, from Basketball-Reference's list of seasons.
    public static func champions(html: String, teams: [TeamRef]) -> [Int: String] {
        var champions: [Int: String] = [:]
        let pattern = /data-stat="lg_id"[^>]*><a[^>]*>(NBA|BAA)<.*?data-stat="champion"[^>]*><a href="\/teams\/([A-Z]{3})\/(\d{4})\.html"/
            .dotMatchesNewlines()
        for row in Text.rows(html) {
            guard let match = row.firstMatch(of: pattern), let year = Int(match.3) else { continue }
            let code = String(match.2)
            let id = Teams.resolve(franchises[code] ?? code, in: teams)
            if !id.isEmpty { champions[year] = id }
        }
        return champions
    }

    /// The winner of the Cup final, when the scoreboard of that day holds it and it is over.
    public static func cupFinal(scoreboard: JSON) -> CupFinal? {
        for event in scoreboard["events"].array {
            let comp = event["competitions"][0]
            let notes = comp["notes"].array.map { $0["headline"].text }.joined(separator: " ")
            guard notes.contains("Championship"), notes.contains("Cup") || notes.contains("Tournament"),
                  comp["status"]["type"]["completed"].bool == true,
                  let winner = comp["competitors"].array.first(where: { $0["winner"].bool == true }) else { continue }
            return CupFinal(teamID: winner["team"]["id"].text, date: event["date"].text)
        }
        return nil
    }

    /// The player's games of a season, preseason left out, by date.
    public static func games(gamelog: JSON) -> [LogGame] {
        var ids: Set<String> = []
        for type in gamelog["seasonTypes"].array where !type["displayName"].text.contains("Preseason") {
            for category in type["categories"].array {
                for event in category["events"].array { ids.insert(event["eventId"].text) }
            }
        }
        let events = gamelog["events"].raw as? [String: Any] ?? [:]
        return events.filter { ids.contains($0.key) }
            .map { LogGame(date: JSON($0.value)["gameDate"].text, teamID: JSON($0.value)["team"]["id"].text) }
            .sorted { $0.date < $1.date }
    }

    /// The seasons whose game log is needed: those the player spent, at least in part, with the winner.
    public static func candidates(career: [StatLine], champions: [Int: String], cups: [Int: CupFinal]) -> (nba: [Int], cup: [Int]) {
        let teams = teamsBySeason(career)
        return (champions.filter { teams[Season.label($0.key)]?.contains($0.value) == true }.keys.sorted(),
                cups.filter { teams[Season.label($0.key)]?.contains($0.value.teamID) == true }.keys.sorted())
    }

    /// His last game of the season says where he was for the NBA title (a player traded away in February did
    /// not win it), his last game up to the final for the Cup. Without a game log (old seasons), a season
    /// spent with that team only counts.
    public static func won(career: [StatLine], champions: [Int: String], cups: [Int: CupFinal], logs: [Int: [LogGame]]) -> [Award] {
        let teams = teamsBySeason(career)
        func onTeam(_ season: Int, _ team: String, until: String? = nil) -> Bool {
            guard let log = logs[season], !log.isEmpty else { return teams[Season.label(season)] == [team] }
            let before = log.filter { until == nil || $0.date.prefix(16) <= until!.prefix(16) }
            return (before.last ?? log[0]).teamID == team
        }
        let (nba, cup) = candidates(career: career, champions: champions, cups: cups)
        let titles = [
            ("NBA Champion", nba.filter { onTeam($0, champions[$0]!) }),
            ("NBA Cup Champion", cup.filter { onTeam($0, cups[$0]!.teamID, until: cups[$0]!.date) }),
        ]
        return titles.filter { !$0.1.isEmpty }.map { Award(name: $0.0, seasons: $0.1.sorted(by: >).map(Season.label)) }
    }

    private static func teamsBySeason(_ career: [StatLine]) -> [String: Set<String>] {
        var teams: [String: Set<String>] = [:]
        for line in career where !line.teamID.isEmpty {
            // ESPN names the seasons before 1993-94 by the year they end: "1993".
            let season = Int(line.label).map(Season.label) ?? line.label
            teams[season, default: []].insert(line.teamID)
        }
        return teams
    }
}
