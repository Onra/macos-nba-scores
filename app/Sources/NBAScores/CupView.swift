import NBAKit
import SwiftUI

struct CupView: View {
    let model: AppModel
    let cup: CupData

    static let columns = ["W-L", "Diff", "PF", "PA", "GB"]
    static let widths: [CGFloat] = [38, 42, 38, 38, 28]

    var body: some View {
        if !cup.hasGames {
            Placeholder(text: "No NBA Cup games yet")
        } else {
            // The knockout tree: under the groups while they are played, on top once the quarterfinals are set.
            VStack(spacing: 20) {
                if cup.bracket.set { tree }
                HStack(alignment: .top, spacing: 16) {
                    column("West")
                    column("East")
                }
                if !cup.bracket.set { tree }
            }
            .padding(.vertical, 6)
        }
    }

    private var tree: some View {
        VStack(spacing: 8) {
            SectionHeader(title: cup.bracket.projected && !cup.bracket.set ? "Knockout rounds · projected" : "Knockout rounds")
            CupTree(model: model, bracket: cup.bracket)
        }
    }

    private func column(_ conf: String) -> some View {
        VStack(spacing: 14) {
            ForEach(cup.groups.filter { $0.conf == conf }) { group in
                VStack(spacing: 1) {
                    SectionHeader(title: group.name, columns: CupView.columns, widths: CupView.widths)
                    ForEach(group.teams) { team in
                        row(team, started: group.started)
                        // The group winner goes through.
                        if group.started, team.rank == 1 { CutLine() }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ team: CupRow, started: Bool) -> some View {
        Row(height: 26, action: team.teamID.isEmpty ? nil : { model.openTeam(team.teamID, season: Season.endYear(cup.season)) }) {
            HStack(spacing: 6) {
                Text(started ? "\(team.rank)" : "")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, alignment: .trailing)
                RemoteImage(team.logo).frame(width: 20, height: 20)
                Text(team.name).font(.system(size: 13)).lineLimit(1)
                if !team.tag.isEmpty {
                    Text(team.tag).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accentColor).lineLimit(1)
                }
                Spacer(minLength: 0)
                Cells(values: [team.record, team.diff, "\(team.pointsFor)", "\(team.pointsAgainst)", team.gamesBehind],
                      widths: CupView.widths, bold: [0])
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .opacity(team.eliminated ? 0.55 : 1)
        }
    }
}

/// The knockout rounds: West on the left, East on the right, the final and the champion in the middle.
struct CupTree: View {
    let model: AppModel
    let bracket: CupBracket

    private let card = CGSize(width: 108, height: 44)
    private let width: CGFloat = 660
    private let quarters: [CGFloat] = [70, 148]
    private let middle: CGFloat = 109
    private let height: CGFloat = 196

    private var gap: CGFloat { (width - 5 * card.width) / 4 }
    private func left(_ column: Int) -> CGFloat { CGFloat(column) * (card.width + gap) }
    private func center(_ column: Int) -> CGFloat { left(column) + card.width / 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            BracketLines(links: links).stroke(.primary.opacity(0.2), lineWidth: 1)
            Caption("West").position(x: center(0), y: quarters[0] - card.height / 2 - 12)
            Caption("East").position(x: center(4), y: quarters[0] - card.height / 2 - 12)
            ForEach(0..<2, id: \.self) { i in
                game(bracket.west.quarterfinals[i]).position(x: center(0), y: quarters[i] + 9)
                game(bracket.east.quarterfinals[i]).position(x: center(4), y: quarters[i] + 9)
            }
            game(bracket.west.semifinal).position(x: center(1), y: middle + 9)
            game(bracket.east.semifinal).position(x: center(3), y: middle + 9)
            game(bracket.final, accented: true).position(x: center(2), y: middle + 9)
            if let champion = bracket.champion {
                VStack(spacing: 3) {
                    Image(systemName: "trophy.fill").font(.system(size: 22)).foregroundStyle(.yellow)
                    HStack(spacing: 5) {
                        RemoteImage(champion.logo).frame(width: 18, height: 18)
                        Text(champion.abbr).font(.system(size: 13, weight: .bold))
                    }
                }
                .position(x: center(2), y: 36)
            }
        }
        .frame(width: width, height: height)
    }

    /// A card with, under it, when the game is played or how it ended.
    private func game(_ game: CupCard, accented: Bool = false) -> some View {
        func line(_ side: CupSide, other: CupSide) -> BracketCard.Line {
            BracketCard.Line(seed: side.seed, abbr: side.abbr, logo: side.logo,
                             figure: game.state == .pre ? "" : side.score,
                             bold: side.winner, dimmed: other.winner, projected: side.projected)
        }
        return VStack(spacing: 4) {
            BracketCard(top: line(game.top, other: game.bottom), bottom: line(game.bottom, other: game.top),
                        width: card.width, accented: accented, live: game.state == .live,
                        action: game.id.isEmpty || game.state == .pre ? nil : { model.openBox(id: game.id) })
            Text(when(game))
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(game.state == .live ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                .frame(height: 14)
        }
    }

    /// When the game is played, or how it ended. A game whose teams are not known has a day but no hour yet.
    private func when(_ game: CupCard) -> String {
        if game.day.isEmpty { return " " }
        let known = !game.top.nick.isEmpty && !game.bottom.nick.isEmpty && !game.top.projected && !game.bottom.projected
        if game.state == .pre, !known { return GameDay.label(game.day) }
        return gameWhen(day: game.day, date: game.date, state: game.state, detail: game.detail)
    }

    private var links: [BracketLines.Link] {
        var links: [BracketLines.Link] = []
        for y in quarters {
            links.append(.init(from: CGPoint(x: left(0) + card.width, y: y), to: CGPoint(x: left(1), y: middle)))
            links.append(.init(from: CGPoint(x: left(4), y: y), to: CGPoint(x: left(3) + card.width, y: middle)))
        }
        links.append(.init(from: CGPoint(x: left(1) + card.width, y: middle), to: CGPoint(x: left(2), y: middle)))
        links.append(.init(from: CGPoint(x: left(3), y: middle), to: CGPoint(x: left(2) + card.width, y: middle)))
        return links
    }
}
