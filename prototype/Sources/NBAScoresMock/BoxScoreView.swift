import SwiftUI

struct BoxScoreView: View {
    let nav: Nav

    static let columns = ["MIN", "PTS", "REB", "AST", "STL", "BLK", "TO", "FG", "3PT", "FT", "+/-"]
    static let widths: [CGFloat] = [34, 34, 34, 34, 30, 30, 30, 50, 46, 46, 36]

    var body: some View {
        VStack(spacing: 18) {
            LineScore(teams: Mock.box).padding(.top, 6)
            ForEach(Mock.box, id: \.team) { box in
                TeamBoxView(box: box) { nav.open(.player) }
            }
        }
        .padding(.bottom, 6)
    }
}

struct LineScore: View {
    let teams: [TeamBox]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 76, height: 1)
                ForEach(1...4, id: \.self) { Caption("\($0)").frame(width: 36, alignment: .trailing) }
                Caption("T").frame(width: 46, alignment: .trailing)
            }
            ForEach(teams, id: \.team) { box in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Logo(team: box.team, size: 18)
                        Text(box.team.abbr).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(width: 76, alignment: .leading)
                    ForEach(box.quarters.indices, id: \.self) { i in
                        Text("\(box.quarters[i])").foregroundStyle(.secondary).frame(width: 36, alignment: .trailing)
                    }
                    Text("\(box.score)").fontWeight(.semibold).frame(width: 46, alignment: .trailing)
                }
                .font(.system(size: 12))
                .monospacedDigit()
            }
        }
    }
}

struct TeamBoxView: View {
    let box: TeamBox
    let openPlayer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Logo(team: box.team, size: 24)
                Text(box.team.fullName).font(.system(size: 14, weight: .semibold))
                Text("\(box.score)").font(.system(size: 14)).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, Layout.rowInset)
            .padding(.bottom, 10)

            let top = (box.starters + box.bench).max { (Int($0.stats[1]) ?? 0) < (Int($1.stats[1]) ?? 0) }?.id
            group("Starters", box.starters, top: top)
            group("Bench", box.bench, top: top).padding(.top, 8)

            ForEach(box.dnp, id: \.name) { player in
                Row(height: 24) {
                    HStack(spacing: 6) {
                        Text(player.name).font(.system(size: 12))
                        Text("DNP · \(player.reason)").font(.system(size: 11))
                    }
                    .foregroundStyle(.tertiary)
                }
            }

            Divider().padding(.horizontal, Layout.rowInset).padding(.top, 2)
            Row(height: 26) {
                HStack(spacing: 0) {
                    Text("Total").font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                    Cells(values: box.totals, widths: BoxScoreView.widths).font(.system(size: 12, weight: .semibold))
                }
            }
            Text(box.summary)
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Layout.rowInset)
                .padding(.top, 4)
        }
    }

    private func group(_ title: String, _ players: [PlayerLine], top: String?) -> some View {
        VStack(spacing: 2) {
            SectionHeader(title: title, columns: BoxScoreView.columns, widths: BoxScoreView.widths)
            ForEach(players) { player in
                Row(height: 24, action: openPlayer) {
                    HStack(spacing: 0) {
                        Text(player.name).font(.system(size: 12.5)).lineLimit(1)
                        Text(player.pos).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 5)
                        Spacer(minLength: 0)
                        Cells(values: player.stats, widths: BoxScoreView.widths, bold: player.id == top ? [1] : [])
                            .font(.system(size: 12))
                    }
                }
            }
        }
    }
}
