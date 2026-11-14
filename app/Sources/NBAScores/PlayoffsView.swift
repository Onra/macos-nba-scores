import NBAKit
import SwiftUI

struct PlayoffsView: View {
    let model: AppModel
    let bracket: PlayoffBracket

    var body: some View {
        VStack(spacing: 22) {
            PlayoffTree(model: model, bracket: bracket).padding(.top, 8)
            if bracket.west.hasPlayIn || bracket.east.hasPlayIn {
                HStack(alignment: .top, spacing: 16) {
                    playIn("Play-in · West", bracket.west)
                    playIn("Play-in · East", bracket.east)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func playIn(_ title: String, _ conference: ConferenceBracket) -> some View {
        VStack(spacing: 2) {
            if conference.hasPlayIn {
                SectionHeader(title: title)
                ForEach(conference.playIn) { slot in
                    BracketGameRow(model: model, label: slot.label, game: slot.game)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// West on the left, East on the right, the Finals and the champion in the middle.
struct PlayoffTree: View {
    let model: AppModel
    let bracket: PlayoffBracket

    private let width = Bracket.width
    private let card = CGSize(width: 92, height: 44)
    private let headerHeight: CGFloat = 20
    private let r1: [CGFloat] = [22, 80, 138, 196]
    private let semis: [CGFloat] = [51, 167]
    private let finals: CGFloat = 109
    private let height: CGFloat = 218

    private var gap: CGFloat { (width - 7 * card.width) / 6 }
    private func left(_ column: Int) -> CGFloat { CGFloat(column) * (card.width + gap) }
    private func center(_ column: Int) -> CGFloat { left(column) + card.width / 2 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(headers.enumerated()), id: \.offset) { column, title in
                Caption(title).position(x: center(column), y: 5)
            }
            Group {
                BracketLines(links: links).stroke(.primary.opacity(0.2), lineWidth: 1)
                ForEach(0..<4, id: \.self) { i in
                    series(bracket.west.round1[i]).position(x: center(0), y: r1[i])
                    series(bracket.east.round1[i]).position(x: center(6), y: r1[i])
                }
                ForEach(0..<2, id: \.self) { i in
                    series(bracket.west.round2[i]).position(x: center(1), y: semis[i])
                    series(bracket.east.round2[i]).position(x: center(5), y: semis[i])
                }
                series(bracket.west.finals).position(x: center(2), y: finals)
                series(bracket.east.finals).position(x: center(4), y: finals)
                series(bracket.finals, accented: true).position(x: center(3), y: finals)
                if let champion = bracket.champion {
                    VStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 22)).foregroundStyle(.yellow)
                        HStack(spacing: 5) {
                            RemoteImage(champion.logo).frame(width: 18, height: 18)
                            Text(champion.abbr).font(.system(size: 13, weight: .bold))
                        }
                    }
                    .position(x: center(3), y: 38)
                }
                Caption("Finals").position(x: center(3), y: finals + card.height / 2 + 12)
            }
            .offset(y: headerHeight)
        }
        .frame(width: width, height: height + headerHeight)
    }

    private var headers: [String] {
        ["West · R1", "Semis", "West finals", "", "East finals", "Semis", "East · R1"]
    }

    private func series(_ series: SeriesCard, accented: Bool = false) -> some View {
        func line(_ side: SeriesSide, other: SeriesSide) -> BracketCard.Line {
            BracketCard.Line(seed: side.seed, abbr: side.abbr, logo: side.logo,
                             figure: series.state == .pre ? "" : "\(side.wins)",
                             bold: side.winner, dimmed: other.winner, projected: side.projected)
        }
        return BracketCard(top: line(series.top, other: series.bottom), bottom: line(series.bottom, other: series.top),
                           accented: accented, live: series.state == .live,
                           action: series.games.isEmpty ? nil : { model.openSeries(series) })
    }

    private var links: [BracketLines.Link] {
        var links: [BracketLines.Link] = []
        for i in 0..<4 {
            links.append(.init(from: CGPoint(x: left(0) + card.width, y: r1[i]), to: CGPoint(x: left(1), y: semis[i / 2])))
            links.append(.init(from: CGPoint(x: left(6), y: r1[i]), to: CGPoint(x: left(5) + card.width, y: semis[i / 2])))
        }
        for i in 0..<2 {
            links.append(.init(from: CGPoint(x: left(1) + card.width, y: semis[i]), to: CGPoint(x: left(2), y: finals)))
            links.append(.init(from: CGPoint(x: left(5), y: semis[i]), to: CGPoint(x: left(4) + card.width, y: finals)))
        }
        links.append(.init(from: CGPoint(x: left(2) + card.width, y: finals), to: CGPoint(x: left(3), y: finals)))
        links.append(.init(from: CGPoint(x: left(4), y: finals), to: CGPoint(x: left(3) + card.width, y: finals)))
        return links
    }
}

/// The games of one series, in order.
struct SeriesView: View {
    let model: AppModel
    let series: SeriesCard

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(series.games.enumerated()), id: \.element.id) { index, game in
                BracketGameRow(model: model, label: "Game \(game.number > 0 ? game.number : index + 1)", game: game)
            }
        }
        .padding(.vertical, 6)
    }
}
