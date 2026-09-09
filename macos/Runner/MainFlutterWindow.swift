import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var flutterViewController: FlutterViewController?
  private var backgroundEffectView: NSView?
  private var windowAppearanceChannel: FlutterMethodChannel?
  private var appearanceBaseline: WindowAppearanceBaseline?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear
    self.flutterViewController = flutterViewController
    appearanceBaseline = WindowAppearanceBaseline(window: self)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.center()

    backgroundEffectView = WindowAppearanceController.installBackground(
      in: flutterViewController.view
    )

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

    self.minSize = NSSize(width: 480, height: 500)
  }

  func applyGlassMode(_ enabled: Bool) {
    guard
      let backgroundEffectView,
      let appearanceBaseline
    else { return }
    WindowAppearanceController.apply(
      glassMode: enabled,
      to: self,
      backgroundEffectView: backgroundEffectView,
      baseline: appearanceBaseline
    )
  }
}
