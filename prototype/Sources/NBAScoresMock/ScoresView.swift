import SwiftUI

struct ScoresView: View {
    let nav: Nav

    var body: some View {
        let games = Mock.days[nav.day].games
        VStack(spacing: 0) {
            ForEach(games) { game in
                GameRow(game: game) { nav.open(.box(game.id)) }
                if game.id != games.last?.id {
                    Divider().padding(.horizontal, Layout.rowInset)
                }
            }
        }
    }
}

struct GameRow: View {
    let game: Game
    let open: () -> Void

    var body: some View {
        Row(action: open) {
            HStack(spacing: 10) {
                status.frame(width: 76, alignment: .leading)
                VStack(spacing: 5) {
                    TeamLine(side: game.away, dimmed: game.lost(game.away), bold: game.isFinal)
                    TeamLine(side: game.home, dimmed: game.lost(game.home), bold: game.isFinal)
                }
                // Always reserved, so that the scores of every game line up.
                ZStack(alignment: .trailing) { Color.clear.frame(height: 1); trailing }.frame(width: 76)
            }
            .padding(.vertical, 9)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch game.status {
            case .scheduled(let time):
                Text(time).font(.system(size: 12, weight: .medium)).monospacedDigit()
            case .live(let clock):
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(clock).font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.red)
                }
            case .final(let text):
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            if let note = game.note {
                HStack(spacing: 3) {
                    if game.cup { Image(systemName: "trophy.fill").font(.system(size: 8)) }
                    Text(game.cup ? note.replacingOccurrences(of: "NBA Cup · ", with: "") : note)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if game.isFinal {
            RecapButton()
        } else if let odds = game.odds {
            Text(odds)
                .font(.system(size: 10.5))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
        }
    }
}

struct TeamLine: View {
    let side: Side
    let dimmed: Bool
    let bold: Bool

    var body: some View {
        HStack(spacing: 8) {
            Logo(team: side.team).opacity(dimmed ? 0.7 : 1)
            Text(side.team.name).font(.system(size: 13, weight: bold && !dimmed ? .semibold : .regular))
            Text(side.record).font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if let score = side.score {
                Text("\(score)").font(.system(size: 15, weight: dimmed ? .regular : .semibold)).monospacedDigit()
            }
        }
        .foregroundStyle(dimmed ? .secondary : .primary)
    }
}
