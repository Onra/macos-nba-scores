import Foundation

/// A player's injury, with ESPN's estimate of when he is back.
public struct Injury: Codable, Hashable, Sendable {
    /// "Out", "Day-To-Day", "Suspension"
    public var status = ""
    /// "Hamstring", "Knee"
    public var type = ""
    /// The day he is expected back, as a "YYYYMMDD" key; empty when ESPN gives none. An estimate, not a promise.
    public var returnDay = ""
    /// Not expected back this season.
    public var seasonEnding = false

    public init() {}

    /// One entry of ESPN's injuries, as on an athlete's bio or in the league's list.
    init(_ json: JSON) {
        status = json["status"].text
        type = json["details"]["type"].text
        returnDay = GameDay.key(fromISO: json["details"]["returnDate"].text)
        if !GameDay.isKey(returnDay) { returnDay = "" }
        seasonEnding = json["details"]["fantasyStatus"]["abbreviation"].text == "OFS"
    }

    /// "Out · Hamstring"
    public var summary: String {
        [status, type].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "Sun 22 Nov", "Out for the season", or nil when ESPN has no estimate.
    public var returnText: String? {
        if seasonEnding { return "Out for the season" }
        return returnDay.isEmpty ? nil : GameDay.label(returnDay)
    }

    /// For a roster line: "Out · 22 Nov", "Out · season".
    public var short: String {
        if seasonEnding { return "\(status) · season" }
        return returnDay.isEmpty ? status : "\(status) · \(GameDay.shortLabel(returnDay))"
    }
}

public enum Injuries {
    /// ESPN's list of every injured player of the league, by athlete id. The roster of a team says who is
    /// hurt but not for how long; this list does.
    public static func parse(_ json: JSON) -> [String: Injury] {
        var injuries: [String: Injury] = [:]
        for team in json["injuries"].array {
            for entry in team["injuries"].array {
                // The list names the player and links to his page: ".../player/_/id/4396993/tyrese-haliburton".
                guard let id = entry["athlete"]["links"][0]["href"].text.firstMatch(of: /\/id\/(\d+)/).map({ String($0.1) }),
                      injuries[id] == nil else { continue }
                injuries[id] = Injury(entry)
            }
        }
        return injuries
    }
}
