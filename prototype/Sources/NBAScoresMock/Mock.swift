import Foundation

// MARK: Teams

struct Team: Hashable, Sendable {
    let abbr: String
    let slug: String
    let name: String
    let city: String

    var fullName: String { "\(city) \(name)" }
    var logo: URL { URL(string: "https://a.espncdn.com/i/teamlogos/nba/500/\(slug).png")! }
}

enum Teams {
    static let all: [String: Team] = {
        let table = """
        ATL|atl|Hawks|Atlanta
        BOS|bos|Celtics|Boston
        BKN|bkn|Nets|Brooklyn
        CHA|cha|Hornets|Charlotte
        CHI|chi|Bulls|Chicago
        CLE|cle|Cavaliers|Cleveland
        DAL|dal|Mavericks|Dallas
        DEN|den|Nuggets|Denver
        DET|det|Pistons|Detroit
        GS|gs|Warriors|Golden State
        HOU|hou|Rockets|Houston
        IND|ind|Pacers|Indiana
        LAC|lac|Clippers|LA
        LAL|lal|Lakers|Los Angeles
        MEM|mem|Grizzlies|Memphis
        MIA|mia|Heat|Miami
        MIL|mil|Bucks|Milwaukee
        MIN|min|Timberwolves|Minnesota
        NO|no|Pelicans|New Orleans
        NY|ny|Knicks|New York
        OKC|okc|Thunder|Oklahoma City
        ORL|orl|Magic|Orlando
        PHI|phi|76ers|Philadelphia
        PHX|phx|Suns|Phoenix
        POR|por|Trail Blazers|Portland
        SAC|sac|Kings|Sacramento
        SA|sa|Spurs|San Antonio
        TOR|tor|Raptors|Toronto
        UTAH|utah|Jazz|Utah
        WSH|wsh|Wizards|Washington
        """
        var teams: [String: Team] = [:]
        for line in table.split(separator: "\n") {
            let f = line.split(separator: "|").map(String.init)
            teams[f[0]] = Team(abbr: f[0], slug: f[1], name: f[2], city: f[3])
        }
        return teams
    }()

    static subscript(_ abbr: String) -> Team { all[abbr]! }
}

// MARK: Scores

struct Side: Hashable {
    let team: Team
    let record: String
    var score: Int?
}

struct Game: Identifiable, Hashable {
    enum Status: Hashable {
        case scheduled(String)
        case live(String)
        case final(String)
    }

    let id: Int
    let away: Side
    let home: Side
    let status: Status
    var note: String?
    var cup = false
    var odds: String?

    var isFinal: Bool { if case .final = status { true } else { false } }
    var isLive: Bool { if case .live = status { true } else { false } }

    /// True when the game is over and this side lost.
    func lost(_ side: Side) -> Bool {
        guard isFinal, let a = away.score, let h = home.score else { return false }
        return (side == away ? a : h) < max(a, h)
    }
}

struct GameDay {
    let title: String
    let subtitle: String
    let games: [Game]
}

// MARK: Box score

struct PlayerLine: Identifiable {
    let name: String
    let pos: String
    /// MIN PTS REB AST STL BLK TO FG 3PT FT +/-
    let stats: [String]
    var id: String { name }
}

struct TeamBox {
    let team: Team
    let score: Int
    let quarters: [Int]
    let starters: [PlayerLine]
    let bench: [PlayerLine]
    let dnp: [(name: String, reason: String)]
    let totals: [String]
    let summary: String
}

// MARK: Player

struct StatRow: Identifiable {
    let label: String
    var team: String?
    /// GP MIN PTS REB AST STL BLK TO FG% 3P% FT%
    let values: [String]
    var id: String { label }
}

struct Salary: Identifiable {
    let season: String
    let team: String
    let amount: String
    var note: String?
    var current = false
    var id: String { season }
}

// MARK: Standings and playoffs

struct Standing: Identifiable {
    let seed: Int
    let team: Team
    /// W-L GB HOME AWAY L10 STRK
    let values: [String]
    var id: String { team.abbr }
}

struct Seed {
    let seed: Int
    let team: Team
    let wins: Int
}

struct Series: Identifiable {
    let id: Int
    let top: Seed
    let bottom: Seed
}

struct PlayIn: Identifiable {
    let label: String
    let when: String
    let away: Team
    let awayScore: Int
    let home: Team
    let homeScore: Int
    var id: String { label }
}

// MARK: Mock data

enum Mock {
    static let days: [GameDay] = [
        GameDay(title: "Fri 13 Nov", subtitle: "Regular season · 4 games", games: [
            game(11, "CLE", "8-4", 118, "TOR", "6-6", 109, .final("Final"), note: "NBA Cup · East A", cup: true),
            game(12, "DET", "9-2", 104, "PHI", "6-5", 111, .final("Final"), note: "NBA Cup · East B", cup: true),
            game(13, "SAC", "3-9", 99, "DAL", "4-8", 107, .final("Final"), note: "NBA Cup · West C", cup: true),
            game(14, "MEM", "4-8", 112, "UTAH", "3-8", 116, .final("Final/OT")),
        ]),
        GameDay(title: "Sat 14 Nov", subtitle: "Today · 7 games", games: [
            game(21, "OKC", "9-3", 110, "ATL", "7-5", 113, .final("Final"), note: "ESPN"),
            game(22, "MIA", "6-6", 126, "CHA", "6-5", 127, .final("Final/OT")),
            game(23, "BOS", "8-3", 98, "NY", "8-4", 94, .live("Q4 2:31"), note: "ABC"),
            game(24, "DEN", "7-4", 51, "MIN", "7-5", 48, .live("Q2 7:45"), note: "NBA TV"),
            game(25, "LAL", "8-4", nil, "SA", "10-2", nil, .scheduled("03:00"), note: "ESPN", odds: "SA -4.5\nO/U 228.5"),
            game(26, "GS", "5-7", nil, "PHX", "7-5", nil, .scheduled("04:00"), odds: "PHX -2.5\nO/U 231.5"),
            game(27, "HOU", "8-3", nil, "LAC", "6-6", nil, .scheduled("04:30"), note: "Prime Video", odds: "HOU -3.5\nO/U 219.5"),
        ]),
        GameDay(title: "Sun 15 Nov", subtitle: "Regular season · 3 games", games: [
            game(31, "MIL", "4-8", nil, "CHI", "4-7", nil, .scheduled("21:30"), odds: "MIL -1.5\nO/U 224.5"),
            game(32, "ORL", "6-6", nil, "BKN", "2-9", nil, .scheduled("00:00"), odds: "ORL -8.5\nO/U 212.5"),
            game(33, "POR", "6-6", nil, "NO", "3-9", nil, .scheduled("01:00"), note: "NBA TV", odds: "POR -3.5\nO/U 226.5"),
        ]),
    ]

    static let today = 1
    static var liveCount: Int { days[today].games.filter(\.isLive).count }

    static func game(_ id: Int) -> Game {
        days.flatMap(\.games).first { $0.id == id } ?? days[today].games[0]
    }

    private static func game(
        _ id: Int, _ away: String, _ awayRecord: String, _ awayScore: Int?,
        _ home: String, _ homeRecord: String, _ homeScore: Int?,
        _ status: Game.Status, note: String? = nil, cup: Bool = false, odds: String? = nil
    ) -> Game {
        Game(
            id: id,
            away: Side(team: Teams[away], record: awayRecord, score: awayScore),
            home: Side(team: Teams[home], record: homeRecord, score: homeScore),
            status: status, note: note, cup: cup, odds: odds
        )
    }

    // Box score of OKC at ATL, whatever game is opened.
    static let venue = "State Farm Arena"
    static let box: [TeamBox] = [
        TeamBox(
            team: Teams["OKC"], score: 110, quarters: [28, 21, 30, 31],
            starters: lines("""
            S. Gilgeous-Alexander|G|36|32|5|7|2|1|2|11-20|2-5|8-9|-2
            J. Williams|F|34|21|6|5|1|0|3|8-17|2-6|3-4|-5
            C. Holmgren|C|31|16|9|2|0|3|1|6-12|1-4|3-3|+1
            L. Dort|G|30|8|4|1|1|0|0|3-8|2-6|0-0|-6
            I. Hartenstein|C|27|9|11|4|1|1|2|4-6|0-0|1-2|-3
            """),
            bench: lines("""
            A. Caruso|G|22|7|3|4|2|0|1|3-6|1-3|0-0|+2
            C. Wallace|G|20|6|2|2|1|0|0|2-5|2-4|0-0|+1
            I. Joe|G|16|8|1|0|0|0|0|3-6|2-5|0-0|-2
            A. Wiggins|F|14|3|3|1|0|0|1|1-4|1-3|0-0|-1
            J. Williams|C|10|0|3|1|0|1|0|0-1|0-0|0-0|0
            """),
            dnp: [("N. Topić", "Injury/Illness"), ("O. Dieng", "Coach's decision")],
            totals: ["", "110", "47", "27", "8", "6", "10", "41-85", "13-36", "15-18", ""],
            summary: "FG 48% · 3PT 36% · FT 83% · Paint 46 · Fast break 10 · Largest lead 4"
        ),
        TeamBox(
            team: Teams["ATL"], score: 113, quarters: [29, 27, 23, 34],
            starters: lines("""
            T. Young|G|35|28|3|11|1|0|4|9-19|4-9|6-6|+6
            D. Daniels|G|34|14|6|4|3|1|1|6-11|1-3|1-2|+4
            Z. Risacher|F|30|15|4|1|1|0|1|6-12|3-7|0-0|+2
            J. Johnson|F|36|22|10|6|1|1|3|8-15|2-5|4-5|+7
            O. Okongwu|C|29|12|9|2|0|2|1|5-8|0-1|2-2|+3
            """),
            bench: lines("""
            K. Porziņģis|C|20|11|5|1|0|2|1|4-8|1-3|2-2|-1
            N. Alexander-Walker|G|22|8|2|3|1|0|1|3-8|2-5|0-0|-2
            L. Kennard|G|14|3|1|2|0|0|0|1-3|1-3|0-0|-3
            M. Gueye|F|10|0|2|0|0|1|0|0-2|0-1|0-0|-1
            """),
            dnp: [("V. Krejčí", "Coach's decision")],
            totals: ["", "113", "42", "30", "7", "7", "12", "42-86", "14-37", "15-17", ""],
            summary: "FG 49% · 3PT 38% · FT 88% · Paint 46 · Fast break 9 · Largest lead 9"
        ),
    ]

    private static func lines(_ table: String) -> [PlayerLine] {
        table.split(separator: "\n").map { line in
            let f = line.split(separator: "|").map(String.init)
            return PlayerLine(name: f[0], pos: f[1], stats: Array(f[2...]))
        }
    }

    // Player card: always the same player.
    static let playerName = "Shai Gilgeous-Alexander"
    static let playerSubtitle = "#2 · Guard · Oklahoma City Thunder"
    static let headshot = URL(string: "https://a.espncdn.com/i/headshots/nba/players/full/4278073.png")!
    static let bio: [(label: String, value: String)] = [
        ("Age", "28  (12/7/1998)"),
        ("Size", "6' 6\" (1.98 m) · 195 lbs (88 kg)"),
        ("Born", "Toronto, ON"),
        ("Draft", "2018: Rd 1, Pk 11 (CHA)"),
        ("College", "Kentucky"),
        ("NBA", "9th Season"),
    ]
    static let injury = "Day-To-Day · Rest"
    static let seasonLabel = "2025-26 season"
    static let averages: [StatRow] = [
        StatRow(label: "Regular season", values: ["68", "33.2", "31.1", "4.3", "6.6", "1.4", "0.8", "2.2", "55.3", "38.6", "87.9"]),
        StatRow(label: "Playoffs", values: ["15", "36.3", "27.6", "2.9", "7.9", "1.3", "0.9", "3.1", "46.3", "30.5", "89.2"]),
        StatRow(label: "Career", values: ["530", "33.1", "25.3", "4.7", "5.3", "1.4", "0.8", "2.3", "50.8", "36.0", "86.4"]),
    ]
    static let salaries: [Salary] = [
        Salary(season: "2030-31", team: "OKC", amount: "$75.6M", note: "player option"),
        Salary(season: "2029-30", team: "OKC", amount: "$70.8M"),
        Salary(season: "2028-29", team: "OKC", amount: "$65.9M"),
        Salary(season: "2027-28", team: "OKC", amount: "$61.0M"),
        Salary(season: "2026-27", team: "OKC", amount: "$40.8M", current: true),
        Salary(season: "2025-26", team: "OKC", amount: "$38.3M"),
        Salary(season: "2024-25", team: "OKC", amount: "$35.9M"),
        Salary(season: "2023-24", team: "OKC", amount: "$33.4M"),
        Salary(season: "2022-23", team: "OKC", amount: "$30.9M"),
        Salary(season: "2021-22", team: "OKC", amount: "$5.5M"),
        Salary(season: "2020-21", team: "OKC", amount: "$4.1M"),
        Salary(season: "2019-20", team: "OKC", amount: "$4.0M"),
        Salary(season: "2018-19", team: "LAC", amount: "$3.4M"),
    ]
    static let awards: [(name: String, seasons: String, title: Bool)] = [
        ("NBA Champion", "2024-25", true),
        ("2× NBA Cup", "2025-26, 2024-25", true),
        ("2× MVP", "2025-26, 2024-25", false),
        ("4× All-NBA 1st Team", "2025-26, 2024-25, 2023-24, 2022-23", false),
        ("Clutch Player of the Year", "2025-26", false),
        ("Finals MVP", "2024-25", false),
        ("All-Rookie 2nd Team", "2018-19", false),
    ]
    static let career: [StatRow] = [
        StatRow(label: "2025-26", team: "OKC", values: ["68", "33.2", "31.1", "4.3", "6.6", "1.4", "0.8", "2.2", "55.3", "38.6", "87.9"]),
        StatRow(label: "2024-25", team: "OKC", values: ["76", "34.2", "32.7", "5.0", "6.4", "1.7", "1.0", "2.4", "51.9", "37.5", "89.8"]),
        StatRow(label: "2023-24", team: "OKC", values: ["75", "34.0", "30.1", "5.5", "6.2", "2.0", "0.9", "2.2", "53.5", "35.3", "87.4"]),
        StatRow(label: "2022-23", team: "OKC", values: ["68", "35.5", "31.4", "4.8", "5.5", "1.6", "1.0", "2.8", "51.0", "34.5", "90.5"]),
        StatRow(label: "2021-22", team: "OKC", values: ["56", "34.7", "24.5", "5.0", "5.9", "1.3", "0.8", "2.8", "45.3", "30.0", "81.0"]),
        StatRow(label: "2020-21", team: "OKC", values: ["35", "33.7", "23.7", "4.7", "5.9", "0.8", "0.7", "3.0", "50.8", "41.8", "80.8"]),
        StatRow(label: "2019-20", team: "OKC", values: ["70", "34.7", "19.0", "5.9", "3.3", "1.1", "0.7", "1.9", "47.1", "34.7", "80.7"]),
        StatRow(label: "2018-19", team: "LAC", values: ["82", "26.5", "10.8", "2.8", "3.3", "1.2", "0.5", "1.7", "47.6", "36.7", "80.0"]),
        StatRow(label: "Career", values: ["530", "33.1", "25.3", "4.7", "5.3", "1.4", "0.8", "2.3", "50.8", "36.0", "86.4"]),
    ]

    // Standings and playoffs of 2025-26.
    static let season = "2025-26"
    static let east = standings("""
    DET 60-22 – 31-9 28-13 8-2 W3
    BOS 56-26 4 30-11 26-15 8-2 W2
    NY 53-29 7 30-10 22-19 6-4 L1
    CLE 52-30 8 27-14 25-16 7-3 W1
    TOR 46-36 14 24-17 22-19 6-4 W1
    ATL 46-36 14 24-17 22-19 6-4 L1
    PHI 45-37 15 23-18 22-19 6-4 W2
    ORL 45-37 15 25-15 19-20 7-3 L1
    CHA 44-38 16 21-20 23-18 6-4 W1
    MIA 43-39 17 26-15 17-24 5-5 W2
    MIL 32-50 28 19-22 13-28 3-7 L1
    CHI 31-51 29 18-23 13-28 2-8 L2
    BKN 20-62 40 12-29 8-33 3-7 L3
    IND 19-63 41 11-30 8-33 3-7 L2
    WSH 17-65 43 11-30 6-35 0-10 L10
    """)
    static let west = standings("""
    OKC 64-18 – 34-7 30-10 7-3 L2
    SA 62-20 2 32-8 29-12 8-2 L1
    DEN 54-28 10 28-13 26-15 10-0 W12
    LAL 53-29 11 28-13 25-16 7-3 W3
    HOU 52-30 12 30-11 22-19 9-1 W1
    MIN 49-33 15 26-15 23-18 5-5 W2
    PHX 45-37 19 25-16 20-21 5-5 W1
    POR 42-40 22 24-17 18-23 7-3 W2
    LAC 42-40 22 23-18 19-22 6-4 W1
    GS 37-45 27 22-19 15-26 3-7 L3
    NO 26-56 38 17-24 9-32 1-9 L2
    DAL 26-56 38 16-25 10-30 3-7 W1
    MEM 25-57 39 13-27 11-29 1-9 L8
    SAC 22-60 42 15-26 7-34 3-7 L1
    UTAH 22-60 42 14-27 8-33 1-9 L1
    """)

    private static func standings(_ table: String) -> [Standing] {
        table.split(separator: "\n").enumerated().map { index, line in
            let f = line.split(separator: " ").map(String.init)
            return Standing(seed: index + 1, team: Teams[f[0]], values: Array(f[1...]))
        }
    }

    private static func series(_ id: Int, _ s1: Int, _ t1: String, _ w1: Int, _ s2: Int, _ t2: String, _ w2: Int) -> Series {
        Series(id: id, top: Seed(seed: s1, team: Teams[t1], wins: w1), bottom: Seed(seed: s2, team: Teams[t2], wins: w2))
    }

    static let westR1 = [
        series(1, 1, "OKC", 4, 8, "PHX", 0), series(2, 4, "LAL", 4, 5, "HOU", 2),
        series(3, 3, "DEN", 2, 6, "MIN", 4), series(4, 2, "SA", 4, 7, "POR", 1),
    ]
    static let westSemis = [series(5, 1, "OKC", 4, 4, "LAL", 0), series(6, 2, "SA", 4, 6, "MIN", 2)]
    static let westFinals = series(7, 1, "OKC", 3, 2, "SA", 4)
    static let eastR1 = [
        series(8, 1, "DET", 4, 8, "ORL", 3), series(9, 4, "CLE", 4, 5, "TOR", 3),
        series(10, 3, "NY", 4, 6, "ATL", 2), series(11, 2, "BOS", 3, 7, "PHI", 4),
    ]
    static let eastSemis = [series(12, 1, "DET", 3, 4, "CLE", 4), series(13, 3, "NY", 4, 7, "PHI", 0)]
    static let eastFinals = series(14, 3, "NY", 4, 4, "CLE", 0)
    static let finals = series(15, 2, "SA", 1, 3, "NY", 4)
    static let champion = Teams["NY"]

    static let playInWest = [
        PlayIn(label: "7 v 8", when: "Tue 14 Apr · Final", away: Teams["POR"], awayScore: 114, home: Teams["PHX"], homeScore: 110),
        PlayIn(label: "9 v 10", when: "Wed 15 Apr · Final", away: Teams["GS"], awayScore: 126, home: Teams["LAC"], homeScore: 121),
        PlayIn(label: "8th seed", when: "Fri 17 Apr · Final", away: Teams["GS"], awayScore: 96, home: Teams["PHX"], homeScore: 111),
    ]
    static let playInEast = [
        PlayIn(label: "7 v 8", when: "Wed 15 Apr · Final", away: Teams["ORL"], awayScore: 97, home: Teams["PHI"], homeScore: 109),
        PlayIn(label: "9 v 10", when: "Tue 14 Apr · Final/OT", away: Teams["MIA"], awayScore: 126, home: Teams["CHA"], homeScore: 127),
        PlayIn(label: "8th seed", when: "Fri 17 Apr · Final", away: Teams["CHA"], awayScore: 90, home: Teams["ORL"], homeScore: 121),
    ]

    static var imageURLs: [URL] { Teams.all.values.map(\.logo) + [headshot] }
}
