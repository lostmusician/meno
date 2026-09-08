import Cocoa

enum WindowAppearanceController {
  static func apply(
    glassMode enabled: Bool,
    to window: NSWindow,
    vibrancyView: NSVisualEffectView
  ) {
    vibrancyView.isHidden = !enabled
    window.isOpaque = !enabled
    window.backgroundColor = enabled ? .clear : .windowBackgroundColor
    window.titlebarAppearsTransparent = enabled
    if enabled {
      window.styleMask.insert(.fullSizeContentView)
    } else {
      window.styleMask.remove(.fullSizeContentView)
    }
  }
}
