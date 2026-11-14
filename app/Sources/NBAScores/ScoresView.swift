import NBAKit
import SwiftUI

struct ScoresView: View {
    let model: AppModel

    var body: some View {
        let games = model.viewGames
        if !model.viewLoaded {
            Placeholder(text: model.error ?? "Loading…", loading: model.error == nil)
        } else if games.isEmpty {
            Placeholder(text: "No games scheduled")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, game in
                    GameRow(
                        game: game, selected: model.selected == index,
                        open: game.hasBoxScore ? { model.openBox(game) } : nil,
                        recap: { model.openRecap(game) }
                    )
                    if index < games.count - 1 {
                        Divider().padding(.horizontal, Layout.rowInset)
                    }
                }
            }
            .onContinuousHover { _ in if model.selected != nil { model.clearSelection() } }
        }
    }
}

struct GameRow: View {
    let game: Game
    let selected: Bool
    let open: (() -> Void)?
    let recap: () -> Void

    var body: some View {
        Row(selected: selected, action: open) {
            HStack(spacing: 10) {
                status.frame(width: 84, alignment: .leading)
                VStack(spacing: 5) {
                    TeamLine(game: game, side: game.away)
                    TeamLine(game: game, side: game.home)
                }
                // Always reserved, so that the scores of every game line up.
                ZStack(alignment: .trailing) { Color.clear.frame(height: 1); trailing }.frame(width: 76)
            }
            .padding(.vertical, 9)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 3) {
            switch (game.state, game.status) {
            case (_, .tipoff(let date)):
                Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: 12, weight: .medium))
            case (.live, .text(let text)):
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.red)
                }
            case (_, .text(let text)):
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            note
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// The Cup round, else the series or note, else the TV network.
    @ViewBuilder private var note: some View {
        let text = game.cup.map { $0 == .group || $0 == .other ? "Cup" : $0.rawValue }
            ?? (game.note.isEmpty ? game.network : game.note)
        if !text.isEmpty {
            HStack(spacing: 3) {
                if game.cup != nil { Image(systemName: "trophy.fill").font(.system(size: 8)) }
                Text(text)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var trailing: some View {
        if game.recapURL != nil {
            RecapButton(action: recap)
        } else if game.state == .pre, !game.odds.isEmpty {
            Text([game.odds, game.overUnder].filter { !$0.isEmpty }.joined(separator: "\n"))
                .font(.system(size: 10.5))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .lineSpacing(2)
                .foregroundStyle(.secondary)
        }
    }
}

struct TeamLine: View {
    let game: Game
    let side: Side

    var body: some View {
        let dimmed = game.lost(side)
        HStack(spacing: 8) {
            Logo(team: side.team).opacity(dimmed ? 0.7 : 1)
            Text(side.team.name)
                .font(.system(size: 13, weight: game.state == .post && !dimmed ? .semibold : .regular))
                .lineLimit(1)
            Text(side.record).font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if game.state != .pre, let score = side.score {
                Text("\(score)").font(.system(size: 15, weight: dimmed ? .regular : .semibold)).monospacedDigit()
            }
        }
        .foregroundStyle(dimmed ? .secondary : .primary)
    }
}
