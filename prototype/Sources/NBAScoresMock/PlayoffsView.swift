import SwiftUI

struct PlayoffsView: View {
    var body: some View {
        VStack(spacing: 22) {
            BracketView().padding(.top, 8)
            HStack(alignment: .top, spacing: 16) {
                playIn("Play-in · West", Mock.playInWest)
                playIn("Play-in · East", Mock.playInEast)
            }
        }
        .padding(.bottom, 6)
    }

    private func playIn(_ title: String, _ games: [PlayIn]) -> some View {
        VStack(spacing: 2) {
            SectionHeader(title: title)
            ForEach(games) { game in
                Row(height: 28, action: {}) {
                    HStack(spacing: 0) {
                        Text(game.label).font(.system(size: 12, weight: .medium)).frame(width: 64, alignment: .leading)
                        Text(game.when).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        let awayWon = game.awayScore > game.homeScore
                        HStack(spacing: 5) {
                            Logo(team: game.away, size: 16)
                            Text("\(game.away.abbr) \(game.awayScore)").fontWeight(awayWon ? .semibold : .regular)
                                .foregroundStyle(awayWon ? .primary : .secondary)
                            Text("–").foregroundStyle(.tertiary)
                            Text("\(game.homeScore) \(game.home.abbr)").fontWeight(awayWon ? .regular : .semibold)
                                .foregroundStyle(awayWon ? .secondary : .primary)
                            Logo(team: game.home, size: 16)
                        }
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .fixedSize()
                    }
                }
            }
        }
    }
}

/// West on the left, East on the right, the finals and the champion in the middle.
struct BracketView: View {
    private let width = Layout.wide - 2 * (Layout.inset + Layout.rowInset)
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
                    SeriesCard(series: Mock.westR1[i]).position(x: center(0), y: r1[i])
                    SeriesCard(series: Mock.eastR1[i]).position(x: center(6), y: r1[i])
                }
                ForEach(0..<2, id: \.self) { i in
                    SeriesCard(series: Mock.westSemis[i]).position(x: center(1), y: semis[i])
                    SeriesCard(series: Mock.eastSemis[i]).position(x: center(5), y: semis[i])
                }
                SeriesCard(series: Mock.westFinals).position(x: center(2), y: finals)
                SeriesCard(series: Mock.eastFinals).position(x: center(4), y: finals)
                SeriesCard(series: Mock.finals, accented: true).position(x: center(3), y: finals)
                champion.position(x: center(3), y: 38)
                Caption("Finals").position(x: center(3), y: finals + card.height / 2 + 12)
            }
            .offset(y: headerHeight)
        }
        .frame(width: width, height: height + headerHeight)
    }

    private var headers: [String] {
        ["West · R1", "Semis", "West finals", "", "East finals", "Semis", "East · R1"]
    }

    private var champion: some View {
        VStack(spacing: 3) {
            Image(systemName: "trophy.fill").font(.system(size: 22)).foregroundStyle(.yellow)
            HStack(spacing: 5) {
                Logo(team: Mock.champion, size: 18)
                Text(Mock.champion.name).font(.system(size: 13, weight: .bold))
            }
        }
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

/// Elbow connectors between a series and the one its winner goes to.
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

struct SeriesCard: View {
    let series: Series
    var accented = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            line(series.top, lost: series.bottom.wins == 4)
            line(series.bottom, lost: series.top.wins == 4)
        }
        .padding(.horizontal, 6)
        .frame(width: 92, height: 44)
        .background(.primary.opacity(hovering ? 0.11 : 0.055), in: .rect(cornerRadius: 7))
        .overlay {
            if accented {
                RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1)
            }
        }
        .onHover { hovering = $0 }
    }

    private func line(_ seed: Seed, lost: Bool) -> some View {
        HStack(spacing: 4) {
            Text("\(seed.seed)").font(.system(size: 9)).foregroundStyle(.tertiary).frame(width: 8)
            Logo(team: seed.team, size: 16).opacity(lost ? 0.7 : 1)
            Text(seed.team.abbr)
            Spacer(minLength: 0)
            Text("\(seed.wins)")
        }
        .font(.system(size: 11.5, weight: seed.wins == 4 ? .semibold : .regular))
        .monospacedDigit()
        .foregroundStyle(lost ? .secondary : .primary)
        .frame(height: 19)
    }
}
