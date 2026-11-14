import AppKit
import NBAKit
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
    private let session = URLSession(configuration: .default)

    func cached(_ url: URL?) -> NSImage? { url.flatMap { images[$0] } }

    func load(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let image = images[url] { return image }
        guard let (data, _) = try? await session.data(from: url), let image = NSImage(data: data) else { return nil }
        images[url] = image
        return image
    }
}

/// A logo or a headshot; shows nothing until it is loaded, then keeps it in memory.
struct RemoteImage: View {
    let url: URL?
    @State private var image: NSImage?

    init(_ url: URL?) {
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

/// A row, highlighted under the pointer when it can be clicked, like a menu item.
struct Row<Content: View>: View {
    var height: CGFloat?
    var selected = false
    var action: (() -> Void)?
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.horizontal, Layout.rowInset)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(highlighted ? 0.06 : 0), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .onTapGesture { action?() }
    }

    private var highlighted: Bool { selected || (hovering && action != nil) }
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Recap", systemImage: "play.fill").font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Open the recap video on NBA.com")
    }
}

/// Loading, nothing to show, or ESPN out of reach.
struct Placeholder: View {
    let text: String
    var loading = false

    var body: some View {
        VStack(spacing: 10) {
            if loading { ProgressView().controlSize(.small) }
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
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

// MARK: Panel window

/// The menu bar item of `MenuBarExtra`, which SwiftUI does not hand out.
@MainActor
enum StatusItem {
    static var window: NSWindow? {
        NSApp.windows.first { $0.className.contains("NSStatusBarWindow") }
    }

    /// Closes the panel the way a click on the menu bar icon does.
    static func closePanel() {
        button(in: window?.contentView)?.performClick(nil)
    }

    private static func button(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap { button(in: $0) }.first
    }
}

/// Watches the panel's window: says when it opens and closes, and keeps it centred under the menu bar icon,
/// as far as the screen allows, whatever its width. Left alone, the system keeps the panel's right edge
/// where it was, so a wider view grows to the left.
struct PanelWindow: NSViewRepresentable {
    let opened: () -> Void
    let closed: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = Watcher()
        view.opened = opened
        view.closed = closed
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Watcher: NSView {
        var opened: () -> Void = {}
        var closed: () -> Void = {}

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let center = NotificationCenter.default
            center.removeObserver(self)
            guard let window else { return }
            center.addObserver(self, selector: #selector(place), name: NSWindow.didResizeNotification, object: window)
            center.addObserver(self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(resignedKey), name: NSWindow.didResignKeyNotification, object: window)
            place()
            if window.isKeyWindow { opened() }
        }

        @objc private func becameKey() {
            place()
            opened()
        }

        @objc private func resignedKey() {
            closed()
        }

        @objc private func place() {
            guard let window, let screen = window.screen ?? NSScreen.main, let icon = StatusItem.window?.frame else { return }
            let visible = screen.visibleFrame
            let width = window.frame.width
            let x = min(max(icon.midX - width / 2, visible.minX + 8), visible.maxX - 8 - width)
            if abs(x - window.frame.origin.x) > 0.5 {
                window.setFrameOrigin(NSPoint(x: x, y: window.frame.origin.y))
            }
        }
    }
}
