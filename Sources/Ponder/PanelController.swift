import AppKit
import Combine
import SwiftUI

/// Hosting view that reports which row the pointer is over and clicks on the header, even while
/// Arena is the active app. The panel has no SwiftUI controls, so it takes every click itself.
final class HoverHostingView: NSHostingView<PanelView> {
    var onHover: ((_ row: Int?, _ header: Bool) -> Void)?
    var onHeaderClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self }.forEach(removeTrackingArea)
        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                owner: self))
    }

    /// Distance from the top of the panel, and whether that is in the header.
    private func locate(_ event: NSEvent) -> (fromTop: CGFloat, header: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let fromTop = isFlipped ? point.y : bounds.height - point.y
        return (fromTop, fromTop >= 0 && fromTop < rootView.model.layout.header)
    }

    override func mouseMoved(with event: NSEvent) {
        let (fromTop, header) = locate(event)
        let layout = rootView.model.layout
        let index = Int(floor((fromTop - layout.header) / layout.row))
        onHover?(fromTop >= layout.header && index >= 0 ? index : nil, header)
    }

    override func mouseExited(with event: NSEvent) { onHover?(nil, false) }

    // Clicks land here rather than on SwiftUI's internal views, and count even though the
    // panel never becomes key (Arena stays the active app).
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if locate(event).header { onHeaderClick?() }
    }
}

@MainActor
final class PanelController {
    private let model: DraftModel
    private let panel: NSPanel
    private let preview: NSPanel
    private let previewImage = NSImageView()
    private var subscriptions: Set<AnyCancellable> = []
    private var timer: Timer?
    /// Show even when Arena isn't the frontmost app (replay / testing).
    private let alwaysVisible: Bool
    /// Stand-in Arena window size for testing layouts without the game.
    private let fakeArena: CGSize?
    /// Size chosen in the menu-bar item.
    var size = PanelSize(rawValue: UserDefaults.standard.string(forKey: "size") ?? "") ?? .full {
        didSet {
            UserDefaults.standard.set(size.rawValue, forKey: "size")
            update()
        }
    }

    init(model: DraftModel, alwaysVisible: Bool, fakeArena: CGSize? = nil) {
        self.model = model
        self.alwaysVisible = alwaysVisible
        self.fakeArena = fakeArena
        // The panel used to be draggable; forget any offset saved back then.
        UserDefaults.standard.removeObject(forKey: "dragX")
        UserDefaults.standard.removeObject(forKey: "dragY")

        panel = Self.makePanel()
        let host = HoverHostingView(rootView: PanelView(model: model))
        panel.contentView = host

        preview = Self.makePanel()
        preview.ignoresMouseEvents = true
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.wantsLayer = true
        previewImage.layer?.cornerRadius = 12
        previewImage.layer?.masksToBounds = true
        preview.contentView = previewImage

        host.onHover = { [weak self] index, header in
            self?.hover(index)
            if self?.model.headerHovered != header { self?.model.headerHovered = header }
        }
        host.onHeaderClick = { [weak model] in
            guard let model else { return }
            model.choose(model.group.next)
        }
        model.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // Follow Arena onto whatever Space it is on, including its fullscreen Space.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        return panel
    }

    // MARK: Visibility and placement

    /// Called when the pack changes and, while a pack is showing, twice a second.
    private func update() {
        let anchor = model.rows.isEmpty ? nil : anchorRect()
        guard let anchor else {
            panel.orderOut(nil)
            preview.orderOut(nil)
            // Keep checking only while there is a pack that could become visible again.
            setPolling(!model.rows.isEmpty)
            return
        }
        setPolling(true)

        // Hang the panel from a point near Arena's top-right corner, below the draft
        // screen's header row.
        let corner = CGPoint(x: anchor.maxX - 8, y: anchor.maxY - anchor.height * 0.16)
        let layout = PanelLayout(scale: size.scale)
        if model.layout != layout { model.layout = layout }
        let size = CGSize(width: layout.width, height: layout.height(rows: model.rows.count))
        var origin = CGPoint(x: corner.x - size.width, y: corner.y - size.height)
        if let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
            origin.x = min(max(origin.x, screen.frame.minX), screen.frame.maxX - size.width)
            origin.y = min(max(origin.y, screen.frame.minY), screen.frame.maxY - size.height)
        }
        let frame = CGRect(origin: origin, size: size)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func setPolling(_ on: Bool) {
        if on, timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
        } else if !on {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Arena's window in AppKit screen coordinates, or nil when the panel should be hidden.
    private func anchorRect() -> CGRect? {
        if let fakeArena, let screen = NSScreen.main?.frame {
            return CGRect(x: screen.minX, y: screen.maxY - fakeArena.height, width: fakeArena.width, height: fakeArena.height)
        }
        let arena = arenaWindow()
        if alwaysVisible { return arena ?? NSScreen.main?.visibleFrame }
        guard NSWorkspace.shared.frontmostApplication?.localizedName == "MTGA" else { return nil }
        return arena
    }

    private func arenaWindow() -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
            let primary = NSScreen.screens.first
        else { return nil }
        let rects: [CGRect] = windows.compactMap { window in
            guard window[kCGWindowOwnerName as String] as? String == "MTGA",
                window[kCGWindowLayer as String] as? Int == 0,
                let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 600, rect.height > 400
            else { return nil }
            // CoreGraphics has a top-left origin; AppKit a bottom-left one.
            return CGRect(x: rect.minX, y: primary.frame.height - rect.maxY, width: rect.width, height: rect.height)
        }
        return rects.max { $0.width * $0.height < $1.width * $1.height }
    }

    // MARK: Hover preview

    private func hover(_ index: Int?) {
        let row = index.flatMap { model.rows.indices.contains($0) ? model.rows[$0] : nil }
        model.hovered = row?.id
        guard let row, let url = row.rating?.url else {
            preview.orderOut(nil)
            return
        }
        Task {
            guard let art = await CardImages.shared.load(url), model.hovered == row.id, panel.isVisible else { return }
            previewImage.image = art.full
            let size = CGSize(width: 280, height: 390)
            let rowMidY = panel.frame.maxY - model.layout.header - (CGFloat(row.id) + 0.5) * model.layout.row
            let screen = panel.screen?.frame ?? .infinite
            // Beside the panel, on whichever side has room.
            var x = panel.frame.minX - size.width - 8
            if x < screen.minX { x = panel.frame.maxX + 8 }
            let y = min(max(rowMidY - size.height / 2, screen.minY + 8), screen.maxY - size.height - 8)
            preview.setFrame(CGRect(origin: CGPoint(x: x, y: y), size: size), display: true)
            preview.orderFrontRegardless()
        }
    }

    // MARK: Testing

    /// Renders the panel's current contents to a PNG.
    func snapshot(to path: String) -> Bool {
        guard let view = panel.contentView, view.bounds.width > 0,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }
}
