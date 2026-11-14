import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(to: args[i + 1])
        } else {
            NBAScoresMockApp.main()
        }
    }
}

struct NBAScoresMockApp: App {
    @State private var nav = Debug.initialNav()

    init() {
        // No Dock icon: menu bar only.
        NSApplication.shared.setActivationPolicy(.accessory)
        StatusMenu.shared.install()
        if CommandLine.arguments.contains("--open") { Debug.openPanel() }
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(nav: nav)
        } label: {
            Image(nsImage: MenuBarIcon.image(live: Mock.liveCount))
        }
        .menuBarExtraStyle(.window)
    }
}

enum MenuBarIcon {
    /// The ball alone, or the ball and `● 3` in the accent colour while three games are live.
    @MainActor static func image(live: Int) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let ball = NSImage(systemSymbolName: "basketball.fill", accessibilityDescription: "NBA Scores")!
            .withSymbolConfiguration(config)!
        guard live > 0 else {
            ball.isTemplate = true
            return ball
        }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let count = "\(live)" as NSString
        let countWidth = ceil(count.size(withAttributes: [.font: font]).width)
        let dot: CGFloat = 6
        let size = NSSize(width: ball.size.width + 5 + dot + 3 + countWidth, height: 18)
        // Drawn on demand, so the label colour follows the menu bar's appearance.
        let image = NSImage(size: size, flipped: false) { rect in
            let tinted = ball.withSymbolConfiguration(config.applying(.init(paletteColors: [.labelColor])))!
            tinted.draw(in: NSRect(x: 0, y: (rect.height - ball.size.height) / 2, width: ball.size.width, height: ball.size.height))
            var x = ball.size.width + 5
            NSColor.controlAccentColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: (rect.height - dot) / 2, width: dot, height: dot)).fill()
            x += dot + 3
            let textHeight = count.size(withAttributes: [.font: font]).height
            count.draw(at: NSPoint(x: x, y: (rect.height - textHeight) / 2),
                       withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// The right-click menu of the menu bar icon. `MenuBarExtra` has none, so right clicks on its button are caught here.
@MainActor
final class StatusMenu: NSObject {
    static let shared = StatusMenu()
    private var launchAtLogin = true

    func install() {
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let window = event.window, window.className.contains("NSStatusBarWindow"),
                  let view = window.contentView else { return event }
            self.menu().popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: view)
            return nil
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Refresh", #selector(refresh), key: "r"))
        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit NBA Scores", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func refresh() {}
    @objc private func toggleLogin() { launchAtLogin.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// `--open [--screen box|player|standings|playoffs]` opens the panel at launch and prints its window number, for screenshots.
@MainActor
enum Debug {
    static func initialNav() -> Nav {
        let nav = Nav()
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screen"), i + 1 < args.count else { return nav }
        switch args[i + 1] {
        case "box": nav.open(.box(21))
        case "player": nav.open(.box(21)); nav.open(.player)
        case "standings": nav.tab = .standings
        case "playoffs": nav.tab = .standings; nav.table = .playoffs
        default: break
        }
        return nav
    }

    static func openPanel() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let bar = NSApp.windows.first { $0.className.contains("NSStatusBarWindow") }
            button(in: bar?.contentView)?.performClick(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                for window in NSApp.windows where window.isVisible {
                    print("WINDOW \(window.windowNumber) \(window.className) \(window.frame)")
                }
                fflush(stdout)
            }
        }
    }

    private static func button(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap { button(in: $0) }.first
    }
}
