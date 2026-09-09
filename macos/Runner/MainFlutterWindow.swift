import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var flutterViewController: FlutterViewController?
  private var windowContentViewController: WindowContentViewController?
  private var windowAppearanceChannel: FlutterMethodChannel?
  private var appearanceBaseline: WindowAppearanceBaseline?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    let windowContentViewController = WindowContentViewController(
      foregroundViewController: flutterViewController
    )
    self.flutterViewController = flutterViewController
    self.windowContentViewController = windowContentViewController
    appearanceBaseline = WindowAppearanceBaseline(window: self)
    let windowFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    let contentSize = self.contentRect(forFrameRect: windowFrame).size
    windowContentViewController.preferredContentSize = contentSize
    windowContentViewController.view.frame = NSRect(
      origin: .zero,
      size: contentSize
    )
    self.setFrame(windowFrame, display: true)
    self.contentViewController = windowContentViewController
    self.minSize = NSSize(width: 900, height: 640)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "meno/window_appearance",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setGlassMode" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let enabled = call.arguments as? Bool else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "setGlassMode expects a boolean",
            details: nil
          )
        )
        return
      }
      self?.applyGlassMode(enabled)
      result(nil)
    }
    windowAppearanceChannel = channel

    super.awakeFromNib()
  }

  func applyGlassMode(_ enabled: Bool) {
    guard
      let windowContentViewController,
      let appearanceBaseline
    else { return }
    WindowAppearanceController.apply(
      glassMode: enabled,
      to: self,
      backgroundEffectView: windowContentViewController.backgroundEffectView,
      baseline: appearanceBaseline
    )
  }
}
