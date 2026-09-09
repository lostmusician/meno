import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  func testWindowContentPlacesVibrancyBehindForeground() {
    let foreground = NSView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    let background = WindowAppearanceController.installBackground(
      in: foreground,
      prefersModernGlass: false
    )
    let vibrancyView = try! XCTUnwrap(
      background as? NSVisualEffectView
    )

    XCTAssertEqual(foreground.subviews.count, 1)
    XCTAssertTrue(foreground.subviews[0] === vibrancyView)
    XCTAssertEqual(vibrancyView.frame, foreground.bounds)
    XCTAssertTrue(vibrancyView.autoresizingMask.contains(.width))
    XCTAssertTrue(vibrancyView.autoresizingMask.contains(.height))
    XCTAssertEqual(vibrancyView.material, .underWindowBackground)
    XCTAssertEqual(vibrancyView.blendingMode, .behindWindow)
    XCTAssertEqual(vibrancyView.state, .followsWindowActiveState)
    XCTAssertTrue(vibrancyView.isHidden)

    foreground.frame = NSRect(x: 0, y: 0, width: 1024, height: 720)
    XCTAssertEqual(vibrancyView.frame, foreground.bounds)

    let center = NSPoint(
      x: foreground.bounds.midX,
      y: foreground.bounds.midY
    )
    XCTAssertNil(vibrancyView.hitTest(center))
    XCTAssertTrue(foreground.hitTest(center) === foreground)
  }

  @available(macOS 26.0, *)
  func testWindowContentUsesRegularGlassOnMacOS26() throws {
    let foreground = NSView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    let background = WindowAppearanceController.installBackground(
      in: foreground
    )
    let glassView = try XCTUnwrap(
      background as? NSGlassEffectView
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
