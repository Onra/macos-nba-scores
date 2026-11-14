import AppKit
import SwiftUI

enum Layout {
    static let compact: CGFloat = 460
    static let detail: CGFloat = 600
    static let wide: CGFloat = 800
    /// Horizontal inset of the content; rows add their own 6 pt so that hover highlights can bleed.
    static let inset: CGFloat = 8
    static let rowInset: CGFloat = 6

    @MainActor static var maxContentHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 90
    }
}

// MARK: Remote images

@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var images: [URL: NSImage] = [:]

    func cached(_ url: URL) -> NSImage? { images[url] }

    func load(_ url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = NSImage(data: data) else { return nil }
        images[url] = image
        return image
    }
}

/// A logo or a headshot; shows nothing until it is loaded, then keeps it in memory.
struct RemoteImage: View {
    let url: URL
    @State private var image: NSImage?

    init(_ url: URL) {
        self.url = url
        _image = State(initialValue: ImageCache.shared.cached(url))
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .task(id: url) { image = await ImageCache.shared.load(url) }
    }
}

struct Logo: View {
    let team: Team
    var size: CGFloat = 22

    var body: some View {
        RemoteImage(team.logo).frame(width: size, height: size)
    }
}

// MARK: Text

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .kerning(0.7)
            .foregroundStyle(.secondary)
    }
}

/// A row of right-aligned figures in fixed-width columns.
struct Cells: View {
    let values: [String]
    let widths: [CGFloat]
    var bold: Set<Int> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values.indices, id: \.self) { i in
                Text(values[i])
                    .fontWeight(bold.contains(i) ? .semibold : nil)
                    .frame(width: widths[i], alignment: .trailing)
            }
        }
        .monospacedDigit()
    }
}

struct SectionHeader: View {
    let title: String
    var columns: [String] = []
    var widths: [CGFloat] = []

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 0) {
                Caption(title)
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(columns.indices, id: \.self) { i in
                        Caption(columns[i]).frame(width: widths[i], alignment: .trailing)
                    }
                }
            }
            Divider()
        }
        .padding(.horizontal, Layout.rowInset)
    }
}

// MARK: Rows and buttons

/// A clickable row: highlighted under the pointer, like a menu item.
struct Row<Content: View>: View {
    var height: CGFloat?
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, Layout.rowInset)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(hovering && action != nil ? 0.06 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .onTapGesture { action?() }
    }
}

struct IconButton: View {
    let symbol: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? .secondary : .quaternary)
        .disabled(!enabled)
    }
}

struct RecapButton: View {
    var body: some View {
        Button {} label: {
            Label("Recap", systemImage: "play.fill").font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

/// Fits its content up to `maxHeight`, and scrolls beyond.
struct Fitted<Content: View>: View {
    let maxHeight: CGFloat
    let screen: AnyHashable
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 320

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .id("top")
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(height, maxHeight))
            .onChange(of: screen) { proxy.scrollTo("top", anchor: .top) }
        }
    }
}

/// Keeps the panel on screen when it grows wider than the space right of the menu bar icon.
struct WindowClamp: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClampView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ClampView: NSView {
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            DispatchQueue.main.async { [weak self] in self?.clamp() }
        }

        private func clamp() {
            guard let window, let screen = window.screen else { return }
            let limit = screen.visibleFrame.maxX - 8
            if window.frame.maxX > limit {
                window.setFrameOrigin(NSPoint(x: limit - window.frame.width, y: window.frame.origin.y))
            }
        }
    }
}
