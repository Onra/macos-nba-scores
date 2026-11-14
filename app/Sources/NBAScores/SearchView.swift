import NBAKit
import SwiftUI

/// The search field in the header: it has the keyboard for as long as the search is open.
struct SearchField: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Teams and players, past and present", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { model.openSelectedResult() }
                .onKeyPress(.upArrow) { model.moveSearch(-1); return .handled }
                .onKeyPress(.downArrow) { model.moveSearch(1); return .handled }
                .onKeyPress(.escape) { model.back(); return .handled }
            if model.searching { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(.primary.opacity(0.06), in: .rect(cornerRadius: 7))
        .onAppear { focused = true }
    }
}

struct SearchView: View {
    let model: AppModel

    var body: some View {
        if model.results.isEmpty {
            let typed = model.query.trimmingCharacters(in: .whitespaces).count >= 2
            Placeholder(text: !typed ? "Bill Russell, the Lakers, the Sonics…" : model.searching ? "Searching…" : "No team or player found")
        } else {
            VStack(spacing: 1) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, result in
                    Row(height: 40, selected: index == model.searchSelected, action: { model.open(result) }) {
                        HStack(spacing: 10) {
                            RemoteImage(result.image)
                                .frame(width: 30, height: 30)
                                .background(.primary.opacity(result.kind == .player ? 0.06 : 0), in: .circle)
                                .clipShape(result.kind == .player ? AnyShape(.circle) : AnyShape(.rect))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(result.name).font(.system(size: 13, weight: .medium))
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(result.kind == .team ? "Team" : "Player").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
