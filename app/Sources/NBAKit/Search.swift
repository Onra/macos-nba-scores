import Foundation

public struct SearchResult: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case team, player }

    public var kind = Kind.player
    /// ESPN's id of the team or the athlete.
    public var target = ""
    public var name = ""
    public var subtitle = ""
    public var image: URL?

    public var id: String { "\(kind.rawValue):\(target):\(name)" }
}

public enum Search {
    public static let limit = 10

    /// Former names of today's franchises, by ESPN abbreviation of the team they are now.
    /// ESPN's search finds retired players but not the franchises that moved or changed name.
    static let aliases: [(name: String, abbr: String, keys: [String])] = [
        ("Seattle SuperSonics", "OKC", ["sonics", "supersonics", "seattle"]),
        ("New Orleans/Oklahoma City Hornets", "NO", ["new orleans hornets", "oklahoma city hornets"]),
        ("Charlotte Bobcats", "CHA", ["bobcats"]),
        ("New Jersey Nets", "BKN", ["new jersey", "nj nets"]),
        ("New York Nets", "BKN", ["new york nets"]),
        ("Vancouver Grizzlies", "MEM", ["vancouver"]),
        ("Washington Bullets", "WSH", ["bullets"]),
        ("Kansas City Kings", "SAC", ["kansas city", "kc kings"]),
        ("Cincinnati Royals", "SAC", ["cincinnati", "royals"]),
        ("San Diego Clippers", "LAC", ["san diego clippers"]),
        ("Buffalo Braves", "LAC", ["buffalo", "braves"]),
        ("Minneapolis Lakers", "LAL", ["minneapolis"]),
        ("San Francisco Warriors", "GS", ["san francisco"]),
        ("Philadelphia Warriors", "GS", ["philadelphia warriors"]),
        ("Syracuse Nationals", "PHI", ["syracuse", "nationals"]),
        ("St. Louis Hawks", "ATL", ["st louis", "saint louis"]),
        ("Fort Wayne Pistons", "DET", ["fort wayne"]),
        ("New Orleans Jazz", "UTAH", ["new orleans jazz"]),
        ("San Diego Rockets", "HOU", ["san diego rockets"]),
    ]

    /// The NBA teams and players of ESPN's site search, in its order.
    public static func parse(_ json: JSON) -> (teams: [SearchResult], players: [SearchResult]) {
        var teams: [SearchResult] = [], players: [SearchResult] = []
        for group in json["results"].array {
            guard let kind = SearchResult.Kind(rawValue: group["type"].text) else { continue }
            for content in group["contents"].array where content["defaultLeagueSlug"].text == "nba" {
                // "s:40~l:46~a:4152" -> "4152" ("a" for an athlete, "t" for a team)
                let marker = kind == .team ? "~t:" : "~a:"
                guard let range = content["uid"].text.range(of: marker) else { continue }
                let target = String(content["uid"].text[range.upperBound...].prefix(while: \.isNumber))
                guard !target.isEmpty else { continue }
                let result = SearchResult(kind: kind, target: target, name: content["displayName"].text,
                                          subtitle: kind == .team ? "" : content["subtitle"].text,
                                          image: URL(string: content["image"]["default"].text))
                if kind == .team { teams.append(result) } else { players.append(result) }
            }
        }
        return (teams, players)
    }

    /// The old franchise names a query matches, as the team they became, leaving out the teams already found.
    public static func aliases(_ query: String, teams: [TeamRef], known: Set<String>) -> [SearchResult] {
        let q = Text.normalizedName(query)
        guard q.count >= 3 else { return [] }
        var known = known, results: [SearchResult] = []
        for alias in aliases {
            guard let team = teams.first(where: { $0.abbr == alias.abbr }), !known.contains(team.id) else { continue }
            let keys = [Text.normalizedName(alias.name)] + alias.keys
            guard keys.contains(where: { q.contains($0) || $0.contains(q) }) else { continue }
            results.append(SearchResult(kind: .team, target: team.id, name: alias.name,
                                        subtitle: "Now the \(team.name)", image: team.logo))
            known.insert(team.id)
        }
        return results
    }

    /// Teams first, then players. The search names the last team of a retired player or a free agent
    /// as if he still played there: `status` (ESPN athlete id -> status) says which he is.
    public static func merge(teams: [SearchResult], players: [SearchResult], status: [String: String]) -> [SearchResult] {
        let labels = ["Inactive": "Retired", "Free Agent": "Free agent"]
        let players = players.map { player in
            var player = player
            if let label = status[player.target].flatMap({ labels[$0] }) { player.subtitle = label }
            if player.image == nil {
                player.image = URL(string: "https://a.espncdn.com/i/headshots/nba/players/full/\(player.target).png")
            }
            return player
        }
        return Array((teams + players).prefix(limit))
    }
}
