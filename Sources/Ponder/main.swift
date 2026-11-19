import AppKit

// Usage:
//   Ponder                                  follow Arena's log via ponder-feed
//   Ponder --replay <events.jsonl>          cycle through recorded packs (--interval <seconds>)
//   Ponder --replay <file> --at <n>         show recorded pack n only
//   ... --snapshot <out.png>                render the panel to a PNG after a few seconds and exit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = DraftModel()
    private var controller: PanelController!
    private var liveFeed: LiveFeed?
    private var replayFeed: ReplayFeed?
    private var statusItem: NSStatusItem!
    private let lastUpdate = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        let replay = value("--replay")
        // --window WxH: pretend Arena's window has this size (top-left of the main screen).
        let window = value("--window").map { $0.split(separator: "x").compactMap { Double($0) } }
        controller = PanelController(
            model: model, alwaysVisible: replay != nil,
            fakeArena: window.flatMap { $0.count == 2 ? CGSize(width: $0[0], height: $0[1]) : nil })
        if let size = value("--size").flatMap(PanelSize.init(rawValue:)) { controller.size = size }
        // --group all|top|middle|bottom: for this run only (the menu choice is what's saved).
        if let group = value("--group").flatMap(PlayerGroup.init(rawValue:)) { model.group = group }
        let onEvent: (DraftEvent) -> Void = { [model] event in model.apply(event) }

        if let replay {
            replayFeed = ReplayFeed(
                path: replay, interval: value("--interval").flatMap(Double.init) ?? 4,
                at: value("--at").flatMap(Int.init), onEvent: onEvent)
            if replayFeed == nil { fail("no draft packs found in \(replay)") }
        } else {
            liveFeed = LiveFeed(onEvent: onEvent)
            if liveFeed == nil { fail("ponder-feed not found; build it or set PONDER_FEED") }
        }

        if let out = value("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [controller] in
                exit(controller!.snapshot(to: out) ? 0 : 1)
            }
        }
        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) { liveFeed?.stop() }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Two angled cards: a template symbol, so macOS tints it for light and dark menu bars.
        if let icon = NSImage(
            systemSymbolName: "rectangle.portrait.on.rectangle.portrait.angled", accessibilityDescription: "Ponder")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "GIH"
        }
        statusItem.button?.toolTip = "Ponder"
        let menu = NSMenu()
        menu.delegate = self
        lastUpdate.isEnabled = false
        menu.addItem(lastUpdate)
        menu.addItem(.separator())
        let sizes = NSMenu()
        for size in PanelSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(setSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.state = size == controller.size ? .on : .off
            sizes.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        let groups = NSMenu()
        for group in PlayerGroup.allCases {
            let item = NSMenuItem(title: group.title, action: #selector(setGroup(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = group.rawValue
            item.state = group == model.group ? .on : .off
            groups.addItem(item)
            if group == .all { groups.addItem(.separator()) }
        }
        let groupItem = NSMenuItem(title: "Ratings from", action: nil, keyEquivalent: "")
        groupItem.submenu = groups
        menu.addItem(groupItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        lastUpdate.title = "Last update: " + Self.ago(model.ratingsUpdated ?? Cache.newestRatings())
    }

    /// "5 minutes ago", "2 hours ago", ...
    private static func ago(_ date: Date?) -> String {
        guard let date else { return "never" }
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(fromTimeInterval: -seconds)
    }

    @objc private func setSize(_ item: NSMenuItem) {
        guard let size = (item.representedObject as? String).flatMap(PanelSize.init(rawValue:)) else { return }
        controller.size = size
        item.menu?.items.forEach { $0.state = $0 === item ? .on : .off }
    }

    @objc private func setGroup(_ item: NSMenuItem) {
        guard let group = (item.representedObject as? String).flatMap(PlayerGroup.init(rawValue:)) else { return }
        model.group = group
        UserDefaults.standard.set(group.rawValue, forKey: "playerGroup")
        item.menu?.items.forEach { $0.state = $0 === item ? .on : .off }
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("ponder: \(message)\n".utf8))
        exit(1)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // menu-bar item only: no Dock icon, never takes focus
    app.run()
}
