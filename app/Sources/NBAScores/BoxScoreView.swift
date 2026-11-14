import NBAKit
import SwiftUI

struct BoxScoreView: View {
    let model: AppModel
    let id: String

    static let widths: [CGFloat] = [34, 34, 34, 34, 30, 30, 30, 50, 46, 46, 36]

    var body: some View {
        if let box = model.boxes[id] {
            VStack(spacing: 18) {
                LineScore(box: box).padding(.top, 6)
                if box.winProbability.count > 1 { WinProbabilityView(box: box) }
                ForEach(box.teams, id: \.side.team.id) { team in
                    TeamBoxView(model: model, team: team)
                }
            }
            .padding(.bottom, 6)
        } else {
            Placeholder(text: model.error ?? "Loading…", loading: model.error == nil)
        }
    }
}

/// The score by period.
struct LineScore: View {
    let box: BoxScore

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 76, height: 1)
                ForEach(box.periods, id: \.self) { Caption($0).frame(width: 36, alignment: .trailing) }
                Caption("T").frame(width: 46, alignment: .trailing)
            }
            ForEach(box.teams, id: \.side.team.id) { team in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Logo(team: team.side.team, size: 18)
                        Text(team.side.team.abbr).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(width: 76, alignment: .leading)
                    ForEach(box.periods.indices, id: \.self) { i in
                        Text(i < team.side.lines.count ? team.side.lines[i] : "")
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    Text(team.side.score.map(String.init) ?? "").fontWeight(.semibold).frame(width: 46, alignment: .trailing)
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        }
    }
}

struct TeamBoxView: View {
    let model: AppModel
    let team: TeamBox

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TeamLink(model: model, team: fullNamed, logoSize: 24, font: .system(size: 14, weight: .semibold))
                Text(team.side.score.map(String.init) ?? "").font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Layout.rowInset)
            .padding(.bottom, 10)

            if team.hasPlayers {
                group("Starters", team.starters)
                if !team.bench.isEmpty || !team.dnp.isEmpty {
                    group("Bench", team.bench).padding(.top, 8)
                }
                ForEach(team.dnp) { player in
                    Row(height: 24, action: { model.openPlayer(player.athlete) }) {
                        HStack(spacing: 6) {
                            Text(player.name).font(.system(size: 12))
                            Text(player.reason.isEmpty ? "DNP" : "DNP · \(player.reason)").font(.system(size: 11))
                        }
                        .foregroundStyle(.tertiary)
                    }
                }
                Divider().padding(.horizontal, Layout.rowInset).padding(.top, 2)
                Row(height: 26) {
                    HStack(spacing: 0) {
                        Text("Total").font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 0)
                        Cells(values: cells(team.totals), widths: BoxScoreView.widths).font(.system(size: 12, weight: .semibold))
                    }
                }
                if !team.summary.isEmpty {
                    Text(team.summary)
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Layout.rowInset)
                        .padding(.top, 4)
                }
            } else {
                Text("No box score yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Layout.rowInset)
            }
        }
    }

    /// The banner names the team in full.
    private var fullNamed: Team {
        var team = team.side.team
        if !team.fullName.isEmpty { team.name = team.fullName }
        return team
    }

    private func cells(_ stats: [String: String]) -> [String] {
        BoxScore.columns.map { stats[$0] ?? "" }
    }

    private func group(_ title: String, _ players: [PlayerLine]) -> some View {
        VStack(spacing: 2) {
            SectionHeader(title: title, columns: BoxScore.columns, widths: BoxScoreView.widths)
            ForEach(players) { player in
                Row(height: 24, action: { model.openPlayer(player.athlete) }) {
                    HStack(spacing: 0) {
                        Text(player.name).font(.system(size: 12.5)).lineLimit(1)
                        Text(player.pos).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 5)
                        Spacer(minLength: 0)
                        Cells(values: cells(player.stats), widths: BoxScoreView.widths, bold: player.top ? [1] : [])
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }
}

/// Each team's chance to win, play after play: the away team's half above the middle line, the home
/// team's below. Dotted lines mark the periods. Hovering shows the clock, the score and the chances
/// at that moment.
struct WinProbabilityView: View {
    let box: BoxScore
    @State var hovered: Int?

    var body: some View {
        let points = box.winProbability
        let away = box.teams.first?.side.team.abbr ?? ""
        let host = box.teams.count == 2 ? box.teams[1].side.team.abbr : ""
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Caption("Win probability")
                Spacer()
                if let hovered, points.indices.contains(hovered) {
                    let point = points[hovered]
                    Text(point.when).foregroundStyle(.secondary)
                    Text("\(away) \(point.awayScore)–\(point.homeScore) \(host)")
                    chance(point.home, away: away, host: host)
                } else if box.state == .live, let last = points.last {
                    chance(last.home, away: away, host: host)
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .frame(height: 14)
            HStack(spacing: 8) {
                VStack {
                    Text(away)
                    Spacer()
                    Text(host)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
                GeometryReader { proxy in
                    Canvas { context, size in draw(in: &context, size: size) }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let count = max(points.count - 1, 1)
                                let index = Int((location.x / proxy.size.width * CGFloat(count)).rounded())
                                hovered = min(max(index, 0), points.count - 1)
                            case .ended:
                                hovered = nil
                            }
                        }
                }
                .frame(height: 64)
                .background(.primary.opacity(0.03), in: .rect(cornerRadius: 6))
            }
        }
        .padding(.horizontal, Layout.rowInset)
    }

    /// The leading team and its chance, `DEN 64%`.
    private func chance(_ home: Double, away: String, host: String) -> some View {
        Text("\(home >= 0.5 ? host : away) \(Int((max(home, 1 - home) * 100).rounded()))%")
            .fontWeight(.semibold)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let points = box.winProbability
        let count = max(points.count - 1, 1)
        func x(_ index: Int) -> CGFloat { size.width * CGFloat(index) / CGFloat(count) }
        // The home team's chance grows downwards, towards its name.
        func y(_ value: Double) -> CGFloat { size.height * CGFloat(value) }
        func vertical(at x: CGFloat) -> Path {
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            return line
        }
        for start in box.periodStarts {
            context.stroke(vertical(at: x(start)), with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
        var middle = Path()
        middle.move(to: CGPoint(x: 0, y: size.height / 2))
        middle.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(middle, with: .color(.primary.opacity(0.2)), lineWidth: 1)

        var curve = Path()
        for (index, point) in points.enumerated() {
            let at = CGPoint(x: x(index), y: y(point.home))
            if index == 0 { curve.move(to: at) } else { curve.addLine(to: at) }
        }
        var area = curve
        area.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        area.addLine(to: CGPoint(x: 0, y: size.height / 2))
        area.closeSubpath()
        context.fill(area, with: .color(.accentColor.opacity(0.15)))
        context.stroke(curve, with: .color(.accentColor), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

        if let hovered, points.indices.contains(hovered) {
            let at = CGPoint(x: x(hovered), y: y(points[hovered].home))
            context.stroke(vertical(at: at.x), with: .color(.primary.opacity(0.35)), lineWidth: 1)
            let dot = Path(ellipseIn: CGRect(x: at.x - 3.5, y: at.y - 3.5, width: 7, height: 7))
            context.fill(dot, with: .color(.accentColor))
            context.stroke(dot, with: .color(.white), lineWidth: 1.5)
        }
    }
}
