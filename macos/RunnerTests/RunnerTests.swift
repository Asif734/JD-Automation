import Cocoa
import FlutterMacOS
import XCTest
@testable import JD_Automation

class RunnerTests: XCTestCase {
  private let window = CGRect(x: 100, y: 100, width: 400, height: 300)
  private let badge = CGRect(x: 164, y: 120, width: 32, height: 32)
  private let bubble = CGRect(x: 204, y: 100, width: 160, height: 100)

  private func image(badges: [CGRect], bubbles: [CGRect], scale: Int = 1,
      marks: [CGRect] = [], exclamation: Bool = true) -> CGImage {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 400 * scale,
        pixelsHigh: 300 * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    let white = NSColor(deviceRed: 1, green: 1, blue: 1, alpha: 1)
    let red = NSColor(deviceRed: 1, green: 0.35, blue: 0.35, alpha: 1)
    let blue = NSColor(deviceRed: 0.85, green: 0.90, blue: 1, alpha: 1)
    for y in 0..<bitmap.pixelsHigh {
      for x in 0..<bitmap.pixelsWide {
        let point = CGPoint(x: CGFloat(x) / CGFloat(scale), y: CGFloat(y) / CGFloat(scale))
        var color = bubbles.contains(where: { $0.contains(point) }) ? blue : white
        for rect in badges {
          let nx = (point.x - rect.minX) / rect.width
          let ny = (point.y - rect.minY) / rect.height
          if pow(nx - 0.5, 2) + pow(ny - 0.5, 2) <= 0.25 {
            color = red
            if exclamation && nx >= 0.42 && nx <= 0.58 &&
                ((ny >= 0.21 && ny <= 0.59) || (ny >= 0.70 && ny <= 0.82)) {
              color = white
            }
          }
        }
        if marks.contains(where: { $0.contains(point) }) {
          color = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        }
        bitmap.setColor(color, atX: x, y: y)
      }
    }
    return bitmap.cgImage!
  }

  private func detect(_ image: CGImage, chat: CGRect? = nil) -> [FailedSendBubble] {
    failedSendBubbles(image: image, windowBounds: window, chatFrame: chat ?? window)
  }

  func testScreenshotSized32PixelFailedIcon() throws {
    let result = try XCTUnwrap(detect(image(badges: [badge], bubbles: [bubble])).first)
    XCTAssertEqual(result.point.x, 280, accuracy: 1)
    XCTAssertEqual(result.point.y, 236, accuracy: 1)
    XCTAssertEqual(result.frame.height, 100, accuracy: 1)
  }

  func testRetinaCoordinates() throws {
    let result = try XCTUnwrap(detect(image(badges: [badge], bubbles: [bubble], scale: 2)).first)
    XCTAssertEqual(result.point.x, 280, accuracy: 1)
    XCTAssertEqual(result.point.y, 236, accuracy: 1)
  }

  func test16PointFailedIcon() {
    let small = CGRect(x: 180, y: 130, width: 16, height: 16)
    XCTAssertEqual(detect(image(badges: [small], bubbles: [bubble], scale: 2)).count, 1)
  }

  func testMultilineReplyAndWatermarkDoNotTruncateBubble() throws {
    let long = CGRect(x: 204, y: 50, width: 160, height: 200)
    let marks = [CGRect(x: 225, y: 133, width: 100, height: 5),
                 CGRect(x: 207, y: 170, width: 10, height: 2)]
    let result = try XCTUnwrap(detect(image(badges: [badge], bubbles: [long], marks: marks)).first)
    XCTAssertEqual(result.frame.height, 200, accuracy: 1)
  }

  func testRedShapesWithoutExclamationAreRejected() {
    XCTAssertTrue(detect(image(badges: [badge], bubbles: [bubble], exclamation: false)).isEmpty)
  }

  func testIconWithoutOutgoingBlueBubbleIsRejected() {
    XCTAssertTrue(detect(image(badges: [badge], bubbles: [])).isEmpty)
  }

  func testOtherChatAndEmojiToolbarAreExcluded() {
    let chat = CGRect(x: 100, y: 100, width: 400, height: 100)
    XCTAssertTrue(detect(image(badges: [badge], bubbles: [bubble]), chat: chat).isEmpty)
  }

  func testClippedMessageIsNotClicked() {
    let clipped = CGRect(x: 204, y: 0, width: 160, height: 200)
    XCTAssertTrue(detect(image(badges: [badge], bubbles: [clipped])).isEmpty)
  }

  func testBubbleFingerprintIgnoresFailedIcon() throws {
    let first = try XCTUnwrap(detect(image(badges: [badge], bubbles: [bubble])).first)
    let shifted = CGRect(x: 164, y: 140, width: 32, height: 32)
    let second = try XCTUnwrap(detect(image(badges: [shifted], bubbles: [bubble])).first)
    XCTAssertEqual(first.fingerprint, second.fingerprint)
  }

  func testBoundedRetryCooldown() {
    XCTAssertEqual((0..<7).map { failedSendRetryDelay(attempts: $0) }, [15, 30, 60, 120, 300, 300, 300])
  }

  func testCroppedChatCoordinatesExcludeSidebar() throws {
    let chat = CGRect(x: 240, y: 150, width: 250, height: 200)
    let result = try XCTUnwrap(detect(image(badges: [badge], bubbles: [bubble]), chat: chat).first)
    XCTAssertEqual(result.point.x, 280, accuracy: 1)
    XCTAssertEqual(result.point.y, 236, accuracy: 1)
  }
}
