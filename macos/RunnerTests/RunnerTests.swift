import Cocoa
import FlutterMacOS
import XCTest

class RunnerTests: XCTestCase {
  func testGlassModeTogglesWindowAppearance() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    let vibrancyView = NSVisualEffectView()

    WindowAppearanceController.apply(
      glassMode: true,
      to: window,
      vibrancyView: vibrancyView
    )
    XCTAssertFalse(vibrancyView.isHidden)
    XCTAssertFalse(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .clear)
    XCTAssertTrue(window.titlebarAppearsTransparent)
    XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))

    WindowAppearanceController.apply(
      glassMode: false,
      to: window,
      vibrancyView: vibrancyView
    )
    XCTAssertTrue(vibrancyView.isHidden)
    XCTAssertTrue(window.isOpaque)
    XCTAssertEqual(window.backgroundColor, .windowBackgroundColor)
    XCTAssertFalse(window.titlebarAppearsTransparent)
    XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
  }
}
