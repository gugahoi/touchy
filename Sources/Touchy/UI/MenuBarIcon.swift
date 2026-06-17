import AppKit

/// The menu-bar status item image: a monochrome hand silhouette derived from the
/// app icon, loaded as a template so macOS tints it for light/dark menu bars.
/// Falls back to an SF Symbol when run outside the .app bundle (e.g. `swift run`).
enum MenuBarIcon {
    static let image: NSImage = {
        let height: CGFloat = 18
        if let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            let width = height * (img.size.width / max(img.size.height, 1))
            img.size = NSSize(width: width, height: height)
            img.isTemplate = true
            return img
        }
        let fallback = NSImage(systemSymbolName: "hand.point.up.left",
                               accessibilityDescription: "Touchy")
            ?? NSImage(size: NSSize(width: height, height: height))
        fallback.isTemplate = true
        return fallback
    }()
}
