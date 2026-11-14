import AppKit
import NBAKit
import ServiceManagement
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(to: args[i + 1])
        } else {
            NBAScoresApp.main()
        }
    }
}

struct NBAScoresApp: App {
    @State private var model: AppModel

    init() {
        // No Dock icon: menu bar only.
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel()
        _model = State(initialValue: model)
        model.start()
        StatusMenu.shared.install(model: model)
        LoginItem.registerOnFirstLaunch()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(model: model)
        } label: {
            Image(nsImage: MenuBarIcon.image(live: model.liveCount))
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
        // Drawn on demand, so that the label colour follows the menu bar's appearance.
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
        image.accessibilityDescription = "NBA Scores, \(live) live"
        return image
    }
}

/// Launch at login, on by default: registered once, then left to the right-click menu.
@MainActor
enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
    }

    static func registerOnFirstLaunch() {
        // Only from the installed app: a debug build run from the terminal has no bundle to register.
        guard Bundle.main.bundleIdentifier != nil, !UserDefaults.standard.bool(forKey: "loginItemRegistered") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemRegistered")
        set(true)
    }
}

/// The right-click menu of the menu bar icon. `MenuBarExtra` has none, so right clicks on its button are caught here.
@MainActor
final class StatusMenu: NSObject {
    static let shared = StatusMenu()
    private var model: AppModel?

    func install(model: AppModel) {
        self.model = model
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let window = event.window, window.className.contains("NSStatusBarWindow"),
                  let view = window.contentView else { return event }
            self.menu().popUp(positioning: nil, at: NSPoint(x: 0, y: -6), in: view)
            return nil
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Refresh", #selector(refresh)))
        menu.addItem(.separator())
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = LoginItem.enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(item("Quit NBA Scores", #selector(quit)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func refresh() { model?.refreshNow() }
    @objc private func toggleLogin() { LoginItem.set(!LoginItem.enabled) }
    @objc private func quit() { NSApp.terminate(nil) }
}
