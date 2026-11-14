import NBAKit
import SwiftUI

/// One of the three tables of a season: the regular season, the NBA Cup or the playoffs.
struct StandingsView: View {
    let model: AppModel
    let key: TableKey

    var body: some View {
        if !model.loaded(key) {
            let failed = model.failedTables.contains(key)
            Placeholder(text: failed ? "Couldn't reach ESPN" : "Loading…", loading: !failed)
        } else {
            switch key.table {
            case .season: SeasonTable(model: model, standings: model.standings[key.season]!, season: key.season)
            case .cup: CupView(model: model, cup: model.cups[key.season]!)
            case .playoffs: PlayoffsView(model: model, bracket: model.brackets[key.season]!)
            }
        }
    }
}

struct SeasonTable: View {
    let model: AppModel
    let standings: Standings
    let season: Int

    static let columns = ["W-L", "GB", "Home", "Away", "L10", "Strk"]
    static let widths: [CGFloat] = [42, 26, 42, 42, 36, 34]

    var body: some View {
        // West on the left, as in the playoff bracket.
        HStack(alignment: .top, spacing: 16) {
            ForEach(standings.conferences.sorted { $0.name > $1.name }) { conference in
                table(conference)
            }
        }
        .padding(.vertical, 6)
    }

    private func table(_ conference: Conference) -> some View {
        VStack(spacing: 1) {
            SectionHeader(title: conference.name, columns: SeasonTable.columns, widths: SeasonTable.widths)
            ForEach(conference.teams) { standing in
                Row(height: 27, action: { model.openTeam(standing.team.id, season: season) }) {
                    HStack(spacing: 6) {
                        Text(standing.seed > 0 ? "\(standing.seed)" : "")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 16, alignment: .trailing)
                        Logo(team: standing.team, size: 20)
                        Text(standing.team.name).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 0)
                        Cells(
                            values: [standing.record, standing.gamesBehind, standing.home, standing.road, standing.lastTen, standing.streak],
                            widths: SeasonTable.widths, bold: [0]
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                }
                // The playoff line under the 6th seed, the play-in line under the 10th.
                if standings.played, standing.seed == 6 || standing.seed == 10 {
                    CutLine(label: standing.seed == 6 ? "Play-in" : "Out")
                }
            }
        }
    }
}

struct CutLine: View {
    var label = ""

    var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                Text(label.uppercased()).font(.system(size: 8.5, weight: .medium)).kerning(0.6).foregroundStyle(.tertiary)
            }
            Rectangle().fill(.primary.opacity(0.18)).frame(height: 1)
        }
        .padding(.horizontal, Layout.rowInset)
        .frame(height: label.isEmpty ? 3 : 9)
    }
}

// MARK: Bracket pieces

enum Bracket {
    static let width = Layout.wide - 2 * (Layout.inset + Layout.rowInset)
}

/// Elbow connectors between a game or a series and the one its winner goes to.
struct BracketLines: Shape {
    struct Link {
        let from: CGPoint
        let to: CGPoint
    }

    let links: [Link]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for link in links {
            let middle = (link.from.x + link.to.x) / 2
            path.move(to: link.from)
            path.addLine(to: CGPoint(x: middle, y: link.from.y))
            path.addLine(to: CGPoint(x: middle, y: link.to.y))
            path.addLine(to: link.to)
        }
        return path
    }
}

/// A two-line card of the tree: a series (wins) or a single game (score).
struct BracketCard: View {
    struct Line {
        var seed = 0
        var abbr = "TBD"
        var logo: URL?
        var figure = ""
        var bold = false
        var dimmed = false
        var projected = false
    }

    let top: Line
    let bottom: Line
    var width: CGFloat = 92
    var accented = false
    var live = false
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            line(top)
            line(bottom)
        }
        .padding(.horizontal, 6)
        .frame(width: width, height: 44)
        .background(.primary.opacity(hovering && action != nil ? 0.11 : 0.055), in: .rect(cornerRadius: 7))
        .overlay {
            if live || accented {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(live ? Color.red.opacity(0.8) : Color.accentColor.opacity(0.8), lineWidth: 1)
            }
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
    }

    private func line(_ line: Line) -> some View {
        HStack(spacing: 4) {
            Text(line.seed > 0 ? "\(line.seed)" : "").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 8)
            RemoteImage(line.logo).frame(width: 16, height: 16).opacity(line.dimmed ? 0.7 : 1)
            Text(line.abbr)
            Spacer(minLength: 0)
            Text(line.figure)
        }
        .font(.system(size: 11.5, weight: line.bold ? .semibold : .regular))
        .monospacedDigit()
        .foregroundStyle(line.abbr == "TBD" ? .tertiary : line.dimmed ? .secondary : .primary)
        // A place the tables give for now.
        .opacity(line.projected ? 0.6 : 1)
        .frame(height: 19)
    }
}

/// "Sat 23 May · Final", or the tip-off time for a game to come.
func gameWhen(day: String, date: String, state: Game.State, detail: String) -> String {
    let label = GameDay.label(day)
    guard state == .pre else { return detail.isEmpty ? label : "\(label) · \(detail)" }
    guard let tipoff = Game.tipoff(date) else { return label }
    return "\(label) · \(tipoff.formatted(date: .omitted, time: .shortened))"
}

/// One play-in or series game: its name, when, and the result with the winner in bold.
struct BracketGameRow: View {
    let model: AppModel
    let label: String
    let game: PlayoffGame?

    var body: some View {
        Row(height: 28, action: game.flatMap { game in game.state == .pre ? nil : { model.openBox(id: game.id) } }) {
            HStack(spacing: 0) {
                Text(label).font(.system(size: 12, weight: .medium)).frame(width: 64, alignment: .leading)
                if let game {
                    Text(gameWhen(day: game.day, date: game.date, state: game.state, detail: game.detail))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(game.state == .live ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 5) {
                        RemoteImage(game.away.logo).frame(width: 16, height: 16)
                        side(game.away, score: game.state != .pre, lost: game.state == .post && !game.away.winner, scoreFirst: false)
                        Text(game.state == .pre ? "at" : "–").foregroundStyle(.tertiary)
                        side(game.home, score: game.state != .pre, lost: game.state == .post && !game.home.winner, scoreFirst: true)
                        RemoteImage(game.home.logo).frame(width: 16, height: 16)
                    }
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .fixedSize()
                } else {
                    Text("To be played").font(.system(size: 11)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func side(_ team: BracketTeam, score: Bool, lost: Bool, scoreFirst: Bool) -> some View {
        let parts = score ? (scoreFirst ? [team.score, team.abbr] : [team.abbr, team.score]) : [team.abbr]
        return Text(parts.joined(separator: " "))
            .fontWeight(score && !lost ? .semibold : .regular)
            .foregroundStyle(lost ? .secondary : .primary)
    }
}
