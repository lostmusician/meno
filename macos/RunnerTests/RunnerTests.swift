import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  func testWindowContentPlacesVibrancyBehindForeground() {
    let foreground = NSViewController()
    let controller = WindowContentViewController(
      foregroundViewController: foreground,
      prefersModernGlass: false
    )
    _ = controller.view
    let vibrancyView = try! XCTUnwrap(
      controller.backgroundEffectView as? NSVisualEffectView
    )

    XCTAssertEqual(controller.view.subviews.count, 2)
    XCTAssertTrue(controller.view.subviews[0] === vibrancyView)
    XCTAssertTrue(controller.view.subviews[1] === foreground.view)
    XCTAssertEqual(vibrancyView.frame, controller.view.bounds)
    XCTAssertEqual(foreground.view.frame, controller.view.bounds)
    XCTAssertTrue(vibrancyView.autoresizingMask.contains(.width))
    XCTAssertTrue(vibrancyView.autoresizingMask.contains(.height))
    XCTAssertTrue(foreground.view.autoresizingMask.contains(.width))
    XCTAssertTrue(foreground.view.autoresizingMask.contains(.height))
    XCTAssertEqual(vibrancyView.material, .underWindowBackground)
    XCTAssertEqual(vibrancyView.blendingMode, .behindWindow)
    XCTAssertEqual(vibrancyView.state, .followsWindowActiveState)
    XCTAssertTrue(vibrancyView.isHidden)

    controller.view.frame = NSRect(x: 0, y: 0, width: 1024, height: 720)
    XCTAssertEqual(vibrancyView.frame, controller.view.bounds)
    XCTAssertEqual(foreground.view.frame, controller.view.bounds)

    let center = NSPoint(
      x: controller.view.bounds.midX,
      y: controller.view.bounds.midY
    )
    XCTAssertNil(vibrancyView.hitTest(center))
    XCTAssertTrue(controller.view.hitTest(center) === foreground.view)
  }

  @available(macOS 26.0, *)
  func testWindowContentUsesRegularGlassOnMacOS26() throws {
    let foreground = NSViewController()
    let controller = WindowContentViewController(
      foregroundViewController: foreground
    )
    _ = controller.view
    let glassView = try XCTUnwrap(
      controller.backgroundEffectView as? NSGlassEffectView
    )

    XCTAssertEqual(glassView.style, .regular)
    XCTAssertEqual(glassView.tintColor, .clear)
    XCTAssertEqual(glassView.cornerRadius, 0)
    XCTAssertTrue(glassView.isHidden)
    XCTAssertNil(glassView.hitTest(.zero))
  }

  func testGlassModeTogglesWindowAppearance() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.backgroundColor = .systemBrown
    window.titlebarAppearsTransparent = false
    let baseline = WindowAppearanceBaseline(window: window)
    let backgroundEffectView = NSView()

    WindowAppearanceController.apply(
      glassMode: true,
      to: window,
      backgroundEffectView: backgroundEffectView,
      baseline: baseline
    )
    XCTAssertFalse(backgroundEffectView.isHidden)
    XCTAssertFalse(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .clear)
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))

    WindowAppearanceController.apply(
      glassMode: false,
      to: window,
      backgroundEffectView: backgroundEffectView,
      baseline: baseline
    )
    XCTAssertTrue(backgroundEffectView.isHidden)
    XCTAssertEqual(window.isOpaque, baseline.isOpaque)
    XCTAssertEqual(window.backgroundColor, baseline.backgroundColor)
    XCTAssertEqual(
      window.titlebarAppearsTransparent,
      baseline.titlebarAppearsTransparent
    )
    XCTAssertEqual(window.styleMask, baseline.styleMask)
  }
}
