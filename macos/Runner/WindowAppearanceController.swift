import Cocoa

struct WindowAppearanceBaseline {
  let isOpaque: Bool
  let backgroundColor: NSColor
  let titlebarAppearsTransparent: Bool
  let styleMask: NSWindow.StyleMask

  init(window: NSWindow) {
    isOpaque = window.isOpaque
    backgroundColor = window.backgroundColor
    titlebarAppearsTransparent = window.titlebarAppearsTransparent
    styleMask = window.styleMask
  }
}

final class PassthroughVisualEffectView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

@available(macOS 26.0, *)
final class PassthroughGlassEffectView: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }
}

enum WindowAppearanceController {
  static func installBackground(
    in foregroundView: NSView,
    prefersModernGlass: Bool = true
  ) -> NSView {
    let backgroundEffectView: NSView
    if #available(macOS 26.0, *), prefersModernGlass {
      let glassView = PassthroughGlassEffectView()
      glassView.style = .regular
      glassView.tintColor = .clear
      glassView.cornerRadius = 0
      backgroundEffectView = glassView
    } else {
      let vibrancyView = PassthroughVisualEffectView()
      vibrancyView.material = .underWindowBackground
      vibrancyView.blendingMode = .behindWindow
      vibrancyView.state = .followsWindowActiveState
      backgroundEffectView = vibrancyView
    }
    backgroundEffectView.frame = foregroundView.bounds
    backgroundEffectView.autoresizingMask = [.width, .height]
    backgroundEffectView.isHidden = true
    foregroundView.addSubview(
      backgroundEffectView,
      positioned: .below,
      relativeTo: nil
    )
    return backgroundEffectView
  }

  static func apply(
    glassMode enabled: Bool,
    to window: NSWindow,
    backgroundEffectView: NSView,
    baseline: WindowAppearanceBaseline
  ) {
    backgroundEffectView.isHidden = !enabled
    let usesModernGlass: Bool
    if #available(macOS 26.0, *) {
      usesModernGlass = backgroundEffectView is NSGlassEffectView
    } else {
      usesModernGlass = false
    }
    if enabled {
      window.isOpaque = false
      window.backgroundColor = .clear
      window.titlebarAppearsTransparent = !usesModernGlass
      if !usesModernGlass {
        window.styleMask.insert(.fullSizeContentView)
      }
    } else {
      window.isOpaque = baseline.isOpaque
      window.backgroundColor = baseline.backgroundColor
      window.titlebarAppearsTransparent = baseline.titlebarAppearsTransparent
      if !usesModernGlass {
        if baseline.styleMask.contains(.fullSizeContentView) {
          window.styleMask.insert(.fullSizeContentView)
        } else {
          window.styleMask.remove(.fullSizeContentView)
        }
      }
    }
  }
}
