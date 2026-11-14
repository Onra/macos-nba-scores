import AppKit
import SwiftUI

/// `--snapshot <dir>` renders every mocked screen to a PNG, in light and dark, without showing anything.
@MainActor
enum Snapshot {
    static func run(to directory: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for url in Mock.imageURLs {
                    group.addTask { _ = await ImageCache.shared.load(url) }
                }
            }
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            for dark in [false, true] {
                for (name, nav) in screens() {
                    let file = "\(directory)/\(name)-\(dark ? "dark" : "light").png"
                    await capture(PanelView(nav: nav), dark: dark, to: file)
                }
                await capture(menuBar, dark: dark, to: "\(directory)/menubar-\(dark ? "dark" : "light").png")
            }
            exit(0)
        }
        app.run()
    }

    private static func screens() -> [(String, Nav)] {
        func nav(_ configure: (Nav) -> Void) -> Nav {
            let nav = Nav()
            configure(nav)
            return nav
        }
        return [
            ("scores", nav { _ in }),
            ("box", nav { $0.open(.box(21)) }),
            ("player", nav { $0.open(.box(21)); $0.open(.player) }),
            ("standings", nav { $0.tab = .standings }),
            ("playoffs", nav { $0.tab = .standings; $0.table = .playoffs }),
        ]
    }

    private static var menuBar: some View {
        HStack(spacing: 18) {
            Image(nsImage: MenuBarIcon.image(live: 0))
            Image(nsImage: MenuBarIcon.image(live: 2))
        }
        .padding(8)
    }

    private static func capture(_ view: some View, dark: Bool, to file: String) async {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 400, height: 400),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.orderFrontRegardless()
        // A few passes: the scroll area takes the height of its content once that is measured.
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            window.setContentSize(host.fittingSize)
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: file))
        }
        window.orderOut(nil)
    }
}
