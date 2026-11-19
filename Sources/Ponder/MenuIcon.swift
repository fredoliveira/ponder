import AppKit

/// The menu-bar icon: three moons (full, half, crescent) in an arch, the half one matching the
/// app icon's moon, drawn as a template image so macOS tints it for light and dark menu bars.
enum MenuIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 26, height: 15)
        let r: CGFloat = 4.25
        let line: CGFloat = 1
        // Centres (origin bottom-left).
        let left = NSPoint(x: 4.85, y: 4.85)
        let middle = NSPoint(x: 13, y: 10.15)
        let right = NSPoint(x: 21.15, y: 4.85)

        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.set()
            func disc(_ c: NSPoint, _ radius: CGFloat = r) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
            }
            func outline(_ c: NSPoint) {
                let ring = disc(c, r - line / 2)
                ring.lineWidth = line
                ring.stroke()
            }

            // Full moon.
            disc(left).fill()

            // Half moon, lit on the left.
            outline(middle)
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: middle.x - r, y: middle.y - r, width: r, height: r * 2).clip()
            disc(middle).fill()
            NSGraphicsContext.restoreGraphicsState()

            // Crescent, lit on the left: the disc minus the same disc shifted right.
            outline(right)
            NSGraphicsContext.saveGraphicsState()
            disc(right).addClip()
            let shadow = disc(NSPoint(x: right.x + 2.6, y: right.y))
            shadow.append(NSBezierPath(rect: NSRect(origin: .zero, size: size)))
            shadow.windingRule = .evenOdd
            shadow.addClip()
            disc(right).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ponder"
        return image
    }
}
