import Foundation

public struct Standing: Identifiable, Hashable, Sendable {
    /// 0 before anyone has played: ESPN then gives no seeds.
    public var seed = 0
    public var team = Team()
    public var record = ""
    public var pct = ""
    public var gamesBehind = ""
    public var home = ""
    public var road = ""
    public var lastTen = ""
    public var streak = ""

    public var id: String { team.id.isEmpty ? team.name : team.id }
}

public struct Conference: Identifiable, Hashable, Sendable {
    public var name = ""
    /// In ESPN's order: seeds, with the NBA tiebreakers applied (a plain sort on win percentage gets ties wrong).
    public var teams: [Standing] = []

    public var id: String { name }
}

public struct Standings: Sendable {
    /// First season ESPN has standings for, by the year it ends.
    public static let firstSeason = 2003

    public var seasonLabel = ""
    /// False until a game of that season has been played.
    public var played = false
    public var conferences: [Conference] = []

    public init(_ json: JSON) {
        seasonLabel = json["season"]["displayName"].string ?? json["season"]["year"].text
        conferences = json["children"].array.map { child in
            var conference = Conference()
            conference.name = child["name"].text
            conference.teams = child["standings"]["entries"].array.map { entry in
                func stat(_ name: String) -> String {
                    entry["stats"].array.first { $0["name"].text == name }?["displayValue"].text ?? ""
                }
                var standing = Standing()
                let t = entry["team"]
                standing.team.id = t["id"].text
                standing.team.abbr = t["abbreviation"].text
                standing.team.name = t["shortDisplayName"].string ?? t["displayName"].string ?? "TBD"
                standing.team.nick = t["name"].text
                standing.team.fullName = t["displayName"].text
                standing.team.logo = URL(string: t["logos"][0]["href"].text)
                standing.seed = Int(stat("playoffSeed")) ?? 0
                standing.record = stat("overall")
                standing.pct = stat("winPercent")
                standing.gamesBehind = stat("gamesBehind")
                standing.home = stat("Home")
                standing.road = stat("Road")
                standing.lastTen = stat("Last Ten Games")
                standing.streak = stat("streak")
                if (Int(stat("wins")) ?? 0) + (Int(stat("losses")) ?? 0) > 0 { played = true }
                return standing
            }
            .sorted {
                let a = $0.seed > 0 ? $0.seed : 99, b = $1.seed > 0 ? $1.seed : 99
                return a != b ? a < b : $0.team.name.localizedCompare($1.team.name) == .orderedAscending
            }
            return conference
        }
    }
}
