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

/// Logos and headshots, kept in memory at the sizes they are drawn at. ESPN's files are 500 pixels wide:
/// scaled down on the fly to a 22-point logo they come out jagged, so each is resampled once, properly,
/// to the pixels it fills.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private struct Key: Hashable {
        let url: URL
        let pixels: Int
    }

    private var files: [URL: Data] = [:]
    private var missing: Set<URL> = []
    private var images: [Key: NSImage] = [:]
    /// The last size drawn of each file, to show at once while the right size is made.
    private var latest: [URL: NSImage] = [:]
    private let session = URLSession(configuration: .default)

    /// ESPN has a version of every team logo for dark backgrounds: the navy ones do not vanish on it.
    static func themed(_ url: URL?, dark: Bool) -> URL? {
        guard dark, let url, url.path.contains("/i/teamlogos/"), url.path.contains("/500/") else { return url }
        return URL(string: url.absoluteString.replacingOccurrences(of: "/500/", with: "/500-dark/")) ?? url
    }

    func cached(_ url: URL?) -> NSImage? { url.flatMap { latest[$0] } }

    /// The image at `url`, resampled so that its longer side is `pixels`; `fallback` when it can't be had.
    func load(_ url: URL?, pixels: Int, fallback: URL? = nil) async -> NSImage? {
        guard let url else { return nil }
        if let image = images[Key(url: url, pixels: pixels)] { return image }
        if files[url] == nil, !missing.contains(url) {
            if let (data, response) = try? await session.data(from: url),
               (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true {
                files[url] = data
            } else if fallback != nil {
                missing.insert(url)
            }
        }
        guard let data = files[url], let image = ImageCache.resample(data, pixels: pixels) else {
            return fallback == url ? nil : await load(fallback, pixels: pixels)
        }
        images[Key(url: url, pixels: pixels)] = image
        latest[url] = image
        return image
    }

    private static func resample(_ data: Data, pixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixels, 16),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return NSImage(data: data) }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}

/// A logo or a headshot; shows nothing until it is loaded, then keeps it in memory. It is made at the
/// size it is given, and team logos follow light and dark mode.
struct RemoteImage: View {
    let url: URL?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?
    @State private var side: CGFloat = 0

    init(_ url: URL?) {
        self.url = url
        _image = State(initialValue: ImageCache.shared.cached(url))
    }

    private struct Request: Equatable {
        let url: URL?
        let pixels: Int
    }

    var body: some View {
        let themed = ImageCache.themed(url, dark: scheme == .dark)
        ZStack {
            Color.clear
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            }
        }
        .onGeometryChange(for: CGFloat.self) { max($0.size.width, $0.size.height) } action: { side = $0 }
        .task(id: Request(url: themed, pixels: Int((side * scale).rounded(.up)))) {
            guard side > 0 else { return }
            if let loaded = await ImageCache.shared.load(themed, pixels: Int((side * scale).rounded(.up)), fallback: url) {
                image = loaded
            }
        }
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

    /// Opens or closes the panel the way a click on the menu bar icon does.
    static func togglePanel() {
        button(in: window?.contentView)?.performClick(nil)
    }

    static func closePanel() {
        togglePanel()
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

// MARK: Titles and awards

/// Lays its views out in lines, right-aligned, wrapping to a new line when the width runs out.
struct TrailingFlow: SwiftUI.Layout {
    var spacing: CGFloat = 0
    var lineSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = self.lines(subviews, width: proposal.width ?? .infinity)
        let width = lines.map(\.width).max() ?? 0
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: min(width, proposal.width ?? width), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(subviews, width: bounds.width) {
            var x = bounds.maxX - line.width
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = lines[lines.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if lines[lines.count - 1].width + extra > width, !lines[lines.count - 1].indices.isEmpty {
                lines.append(Line())
            }
            let added = lines[lines.count - 1].indices.isEmpty ? size.width : size.width + spacing
            lines[lines.count - 1].indices.append(index)
            lines[lines.count - 1].width += added
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
        }
        return lines
    }
}

/// A title or an award and the seasons it was won, each of which may open something.
/// The seasons wrap to more lines when there are many.
struct HonorRow: View {
    let label: String
    let seasons: [String]
    var title = false
    let link: (String) -> (() -> Void)?

    var body: some View {
        Row {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if title {
                    Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
                Text(label).font(.system(size: 12.5)).lineLimit(1).fixedSize()
                Spacer(minLength: 12)
                TrailingFlow {
                    ForEach(Array(seasons.enumerated()), id: \.offset) { index, season in
                        HStack(spacing: 0) {
                            SeasonLink(season: season, action: link(season))
                            if index < seasons.count - 1 { Text(", ") }
                        }
                    }
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 5)
        }
    }
}
