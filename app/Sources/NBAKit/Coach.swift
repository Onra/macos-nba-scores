import Foundation

/// A head coach of a team's season, as Basketball-Reference names him.
public struct CoachRef: Codable, Hashable, Sendable, Identifiable {
    /// Basketball-Reference's code: "carliri01c".
    public var code = ""
    public var name = ""
    /// His record with that team that season: "64-18".
    public var record = ""

    public var id: String { code }
}

/// One season of a coach's career.
public struct CoachSeason: Codable, Hashable, Sendable, Identifiable {
    public var season = ""
    /// The year it ends.
    public var year = 0
    /// Basketball-Reference's team code.
    public var team = ""
    /// ESPN's team id, for the seasons that have a team page.
    public var teamID = ""
    public var assistant = false
    public var wins = 0
    public var losses = 0
    public var pct = ""
    /// Place in the division: "1".
    public var finish = ""
    public var playoffWins: Int?
    public var playoffLosses: Int?
    /// "NBA Champions", "EC Champions"
    public var remark = ""

    public var id: String { "\(season):\(team)" }
    public var record: String { "\(wins)-\(losses)" }
    public var playoffs: String {
        guard let w = playoffWins, let l = playoffLosses else { return "" }
        return "\(w)-\(l)"
    }
    /// "1" -> "1st"
    public var finishText: String {
        guard let n = Int(finish) else { return finish }
        let suffix = (11...13).contains(n % 100) ? "th" : [1: "st", 2: "nd", 3: "rd"][n % 10] ?? "th"
        return "\(n)\(suffix)"
    }
    public var champion: Bool { remark.hasPrefix("NBA Champions") || remark.hasPrefix("BAA Champions") }
}

/// A coach's page: bio, record, titles, awards and career, from Basketball-Reference.
public struct CoachPage: Codable, Sendable, Identifiable {
    public var code = ""
    public var name = ""
    public var photo: URL?
    /// "1959-10-27"
    public var born = ""
    public var birthplace = ""
    public var died = ""
    public var highSchool = ""
    public var college = ""
    /// "Inducted as Coach in 1969"
    public var hallOfFame = ""
    /// "188 G, 2.2 PPG, 0.8 RPG, 1.1 APG"
    public var asPlayer = ""
    /// Newest first: head coach seasons and assistant ones.
    public var seasons: [CoachSeason] = []
    public var wins = 0
    public var losses = 0
    public var pct = ""
    public var playoffWins = 0
    public var playoffLosses = 0
    /// The seasons he was Coach of the Year, newest first.
    public var coachOfTheYear: [String] = []
    /// "Head coach · Indiana Pacers", "Former head coach"
    public var role = ""

    public var id: String { code }

    public init() {}

    public init(code: String, html: String) {
        self.code = code
        let meta = html.range(of: "<div id=\"meta\">").map { String(html[$0.lowerBound...].prefix(8000)) } ?? ""
        func paragraph(_ label: String) -> String {
            guard let match = meta.firstMatch(of: try! Regex("<strong>\\s*\(label):\\s*</strong>(.*?)</p>").dotMatchesNewlines()),
                  let text = match.output[1].substring else { return "" }
            return Text.clean(String(text))
        }
        name = meta.firstMatch(of: /<h1>\s*<span>(.*?)<\/span>/.dotMatchesNewlines()).map { Text.clean(String($0.1)) } ?? ""
        photo = meta.firstMatch(of: /<img[^>]*src="([^"]*\/headshots\/[^"]+)"/).flatMap { URL(string: String($0.1)) }
        born = meta.firstMatch(of: /data-birth="(\d{4}-\d{2}-\d{2})"/).map { String($0.1) } ?? ""
        birthplace = meta.firstMatch(of: /data-birth="[^"]*">[^<]*<\/span>\s*in\s*([^<]+)</).map { Text.clean(String($0.1)) } ?? ""
        died = meta.firstMatch(of: /data-death="(\d{4}-\d{2}-\d{2})"/).map { String($0.1) } ?? ""
        highSchool = paragraph("High School")
        college = paragraph("College")
        // Up to the link to the full list or record.
        hallOfFame = paragraph("Hall of Fame").replacing(/\s*\(Full List\)$/, with: "")
        asPlayer = paragraph("As Player").replacing(/\s*\(Full Record\)$/, with: "")

        // Basketball-Reference hides some tables in HTML comments.
        let page = html.replacingOccurrences(of: "<!--", with: "").replacingOccurrences(of: "-->", with: "")
        var seasons: [CoachSeason] = []
        for row in Text.rows(Text.table("coach-stats", in: page)) {
            let label = Text.cell(row, "season")
            if label == "Career" {
                wins = Int(Text.cell(row, "wins")) ?? 0
                losses = Int(Text.cell(row, "losses")) ?? 0
                pct = Text.cell(row, "win_loss_pct")
                playoffWins = Int(Text.cell(row, "wins_playoffs")) ?? 0
                playoffLosses = Int(Text.cell(row, "losses_playoffs")) ?? 0
                // The totals by team come after: left out.
                break
            }
            guard label.firstMatch(of: /^\d{4}-\d{2}$/) != nil else { continue }
            var season = CoachSeason(season: label, year: Season.endYear(label), team: Text.cell(row, "team_id"))
            season.assistant = !Text.cell(row, "role").isEmpty
            season.wins = Int(Text.cell(row, "wins")) ?? 0
            season.losses = Int(Text.cell(row, "losses")) ?? 0
            season.pct = Text.cell(row, "win_loss_pct")
            season.finish = Text.cell(row, "rank_team")
            season.playoffWins = Int(Text.cell(row, "wins_playoffs"))
            season.playoffLosses = Int(Text.cell(row, "losses_playoffs"))
            season.remark = Text.cell(row, "coach_remarks")
            seasons.append(season)
        }
        self.seasons = seasons.reversed()
        coachOfTheYear = Text.rows(Text.table("coach-awards", in: page))
            .filter { Text.cell($0, "award_id") == "Coach of the Year" && Text.cell($0, "lg_id") == "NBA" }
            .map { Text.cell($0, "season") }
            .sorted(by: >)
    }

    /// The seasons he won the NBA title as head coach, newest first.
    public var titles: [String] { seasons.filter { !$0.assistant && $0.champion }.map(\.season) }

    /// The last season he was a head coach.
    public var lastHeadSeason: CoachSeason? { seasons.first { !$0.assistant } }
    public var headCoach: Bool { lastHeadSeason != nil }

    /// "1017-931 (.522)"
    public var recordText: String { wins + losses > 0 ? "\(wins)-\(losses) (\(pct))" : "" }
    public var playoffsText: String { playoffWins + playoffLosses > 0 ? "\(playoffWins)-\(playoffLosses)" : "" }

    public var birthDate: Date? { Coaches.date(born) }
    public var deathDate: Date? { Coaches.date(died) }

    /// His age, today or when he died.
    public func age(now: Date = Date()) -> Int? {
        guard let birth = birthDate else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: birth, to: deathDate ?? now).year
    }
}

public enum Coaches {
    /// NBA.com's team ids, by ESPN abbreviation.
    public static let nbaTeamIDs = [
        "ATL": "1610612737", "BOS": "1610612738", "BKN": "1610612751", "CHA": "1610612766", "CHI": "1610612741",
        "CLE": "1610612739", "DAL": "1610612742", "DEN": "1610612743", "DET": "1610612765", "GS": "1610612744",
        "HOU": "1610612745", "IND": "1610612754", "LAC": "1610612746", "LAL": "1610612747", "MEM": "1610612763",
        "MIA": "1610612748", "MIL": "1610612749", "MIN": "1610612750", "NO": "1610612740", "NY": "1610612752",
        "OKC": "1610612760", "ORL": "1610612753", "PHI": "1610612755", "PHX": "1610612756", "POR": "1610612757",
        "SAC": "1610612758", "SA": "1610612759", "TOR": "1610612761", "UTAH": "1610612762", "WSH": "1610612764",
    ]

    /// Basketball-Reference's code of a franchise in a season (the year it ends), which follows its moves
    /// and names; "" for a season the franchise did not play.
    public static func bbrefCode(_ abbr: String, season: Int) -> String {
        switch abbr {
        case "OKC": season <= 2008 ? "SEA" : "OKC"
        case "BKN": season <= 2012 ? "NJN" : "BRK"
        case "MEM": season <= 2001 ? "VAN" : "MEM"
        case "WSH": season <= 1997 ? "WSB" : "WAS"
        // The Hornets of 1988-2002 are Charlotte's, as for the NBA; New Orleans started in 2002-03.
        case "CHA": season <= 2002 ? "CHH" : season <= 2004 ? "" : season <= 2014 ? "CHA" : "CHO"
        case "NO": season <= 2002 ? "" : season <= 2005 || (2008...2013).contains(season) ? "NOH" : season <= 2007 ? "NOK" : "NOP"
        default: Teams.bbrefCodes.first { $0.value == abbr }?.key ?? abbr
        }
    }

    /// The head coaches of a team's season, from its page: "Coach: A (30-13), B (2-1), C (17-19)".
    public static func teamCoaches(html: String) -> [CoachRef] {
        guard let line = html.firstMatch(of: /<strong>Coach:<\/strong>(.*?)<\/p>/.dotMatchesNewlines()) else { return [] }
        return String(line.1).matches(of: /href="\/coaches\/([a-z0-9]+)\.html">([^<]+)<\/a>\s*\(([0-9]+-[0-9]+)\)/).map {
            CoachRef(code: String($0.1), name: Text.unescape(String($0.2)), record: String($0.3))
        }
    }

    /// NBA.com's id of a coach of the team whose page this is, found by name.
    public static func nbaCoachID(html: String, name: String) -> String? {
        let key = Text.normalizedName(name)
        for match in html.matches(of: /"COACH_ID":\s*(\d+),.*?"COACH_NAME":\s*"([^"]+)"/) {
            if Text.normalizedName(String(match.2)) == key { return String(match.1) }
        }
        return nil
    }

    public static func nbaHeadshot(_ id: String) -> URL {
        URL(string: "https://cdn.nba.com/headshots/nba/latest/260x190/\(id).png")!
    }

    /// "1959-10-27" -> that day.
    static func date(_ text: String) -> Date? {
        guard !text.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }
}
