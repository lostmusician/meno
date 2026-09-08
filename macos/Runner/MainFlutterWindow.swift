import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var flutterViewController: FlutterViewController?
  private var windowAppearanceChannel: FlutterMethodChannel?
  private let vibrancyView = NSVisualEffectView()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.flutterViewController = flutterViewController
    let windowFrame = NSRect(x: 0, y: 0, width: 1280, height: 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 900, height: 640)
    self.center()

    vibrancyView.frame = flutterViewController.view.bounds
    vibrancyView.autoresizingMask = [.width, .height]
    vibrancyView.material = .underWindowBackground
    vibrancyView.blendingMode = .behindWindow
    vibrancyView.state = .active
    vibrancyView.isHidden = true
    flutterViewController.backgroundColor = .clear
    flutterViewController.view.addSubview(
      vibrancyView,
      positioned: .below,
      relativeTo: nil
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
  }

  func applyGlassMode(_ enabled: Bool) {
    WindowAppearanceController.apply(
      glassMode: enabled,
      to: self,
      vibrancyView: vibrancyView
    )
  }
}
