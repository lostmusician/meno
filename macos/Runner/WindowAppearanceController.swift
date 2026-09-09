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

final class WindowContentViewController: NSViewController {
  let backgroundEffectView: NSView
  let foregroundViewController: NSViewController

  init(
    foregroundViewController: NSViewController,
    prefersModernGlass: Bool = true
  ) {
    self.foregroundViewController = foregroundViewController
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
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    view = NSView()
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    backgroundEffectView.frame = view.bounds
    backgroundEffectView.autoresizingMask = [.width, .height]
    backgroundEffectView.isHidden = true
    view.addSubview(backgroundEffectView)

    addChild(foregroundViewController)
    foregroundViewController.view.frame = view.bounds
    foregroundViewController.view.autoresizingMask = [.width, .height]
    view.addSubview(
      foregroundViewController.view,
      positioned: .above,
      relativeTo: backgroundEffectView
    )
  }
}

enum WindowAppearanceController {
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
