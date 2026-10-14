import Foundation
import CoreGraphics

/// A thread-local, nestable budget for native AX work. A timed-out read poisons
/// its entire snapshot; incomplete identity evidence must never authorize input.
final class AccessibilityBudget {
  private static let key = "com.grozziie.jdAutomation.axBudget"
  static var current: AccessibilityBudget? {
    Thread.current.threadDictionary[key] as? AccessibilityBudget
  }
  private let parent: AccessibilityBudget?
  let deadline: Date
  private let uptimeDeadline: TimeInterval
  private var failed = false

  init(deadline: Date, uptimeDeadline: TimeInterval? = nil) {
    parent = Self.current
    self.deadline = min(deadline, parent?.deadline ?? deadline)
    let localLimit = ProcessInfo.processInfo.systemUptime + max(0, deadline.timeIntervalSinceNow)
    self.uptimeDeadline = min(localLimit, uptimeDeadline ?? localLimit,
                              parent?.uptimeDeadline ?? localLimit)
    Thread.current.threadDictionary[Self.key] = self
  }

  var isCurrent: Bool {
    !failed && (parent?.isCurrent ?? true) &&
      ProcessInfo.processInfo.systemUptime < uptimeDeadline
  }

  func invalidate() {
    failed = true
    parent?.invalidate()
  }

  func close() {
    if let parent { Thread.current.threadDictionary[Self.key] = parent }
    else { Thread.current.threadDictionary.removeObject(forKey: Self.key) }
  }
}

/// Identity evidence is never repaired using OCR lookalikes or prefixes.
enum CustomerSafety {
  struct HeaderLabel {
    let text: String
    let frame: CGRect
  }

  /// JD places the customer name above its quick-transfer control, while the
  /// shop name is separately right-aligned on the same line. Do not treat all
  /// header text as identity evidence, and never choose based on the requested
  /// customer's spelling (that would make verification circular).
  static func activeHeaderIdentity(labels: [HeaderLabel], chatFrame: CGRect,
                                   quickTransferFrames: [CGRect]) -> String? {
    guard chatFrame.width > 0, chatFrame.height > 0 else { return nil }
    let anchors = quickTransferFrames.filter { anchor in
      anchor.width > 0 && anchor.height > 0 &&
        anchor.minX >= chatFrame.minX && anchor.maxX <= chatFrame.maxX &&
        anchor.minY >= chatFrame.minY &&
        anchor.maxY <= chatFrame.minY + max(70, anchor.height * 5)
    }
    guard anchors.count == 1, let anchor = anchors.first else { return nil }
    let alignmentTolerance = max(18, anchor.width * 1.5)
    let labelGap = max(36, anchor.height * 2.5)
    let candidates = labels.filter { label in
      let frame = label.frame
      guard frame.width > 0, frame.height > 0,
            frame.minX >= chatFrame.minX, frame.maxX <= chatFrame.maxX,
            frame.minY >= chatFrame.minY,
            frame.maxY <= anchor.minY + 2,
            frame.maxY >= anchor.minY - labelGap,
            abs(frame.minX - anchor.minX) <= alignmentTolerance else { return false }
      return true
    }
    // Incomplete/conflicting evidence in the customer slot cannot be ignored
    // merely because another candidate is complete.
    guard !candidates.isEmpty,
          candidates.allSatisfy({ fullIdentity($0.text) != nil }) else { return nil }
    return uniqueIdentity(candidates.map(\.text))
  }

  static func operationCurrent(_ deadline: Date, now: Date = Date()) -> Bool {
    now < deadline
  }
  static func fullIdentity(_ raw: String?) -> String? {
    guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty, !value.contains("…"), !value.contains("..."),
          !["Unknown customer", "unknown", "暂无选中的会话"].contains(value),
          !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    else { return nil }
    return value
  }

  static func matches(_ left: String?, _ right: String?) -> Bool {
    guard let a = fullIdentity(left), let b = fullIdentity(right) else { return false }
    return a.utf8.elementsEqual(b.utf8)
  }

  /// Allows a screenshot OCR spelling to be reconciled with the independently
  /// read AX header only for a complete JD identity with one edit at most.
  /// Every later capture/send still requires the exact AX identity.
  static func canReconcileSidebarOCR(_ observed: String?, verifiedAX: String?) -> Bool {
    guard let observed = fullIdentity(observed),
          let verified = fullIdentity(verifiedAX) else { return false }
    if observed.utf8.elementsEqual(verified.utf8) { return true }
    let jdPattern = try! NSRegularExpression(pattern: #"^jd_[A-Za-z0-9]{8,}$"#)
    func isJD(_ value: String) -> Bool {
      jdPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
    }
    guard isJD(observed), isJD(verified),
          abs(observed.count - verified.count) <= 1 else { return false }
    let left = Array(observed.utf8)
    let right = Array(verified.utf8)
    var previous = Array(0...right.count)
    for leftIndex in 1...left.count {
      var current = Array(repeating: 0, count: right.count + 1)
      current[0] = leftIndex
      var rowMinimum = current[0]
      for rightIndex in 1...right.count {
        let substitution = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
        current[rightIndex] = min(
          current[rightIndex - 1] + 1,
          previous[rightIndex] + 1,
          previous[rightIndex - 1] + substitution)
        rowMinimum = min(rowMinimum, current[rightIndex])
      }
      if rowMinimum > 1 { return false }
      previous = current
    }
    return previous.last! <= 1
  }

  static func canRecoverOwnedComposer(owner: String, active: String?,
                                      insertedText: String, currentText: String,
                                      sameElement: Bool) -> Bool {
    matches(owner, active) && sameElement && !insertedText.isEmpty &&
      insertedText.utf8.elementsEqual(currentText.utf8)
  }

  static func uniqueIdentity(_ values: [String]) -> String? {
    let full = values.compactMap(fullIdentity)
    let identities = Set(full.map { Array($0.utf8) })
    return identities.count == 1 ? full.first : nil
  }

  static func uniqueVideoDigest(_ digests: [String]) -> String? {
    guard !digests.isEmpty, digests.allSatisfy({ !$0.isEmpty }) else { return nil }
    return Set(digests).count == 1 ? digests.first : nil
  }

  // Ignore the central play overlay, but require detailed, closely matching
  // colour evidence elsewhere. Flat placeholder thumbnails are not evidence.
  static func videoSignature(_ image: CGImage) -> [Double]? {
    var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
    let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32,
          bitsPerComponent: 8, bytesPerRow: 128,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
      return true
    }
    guard drawn else { return nil }
    var signature: [Double] = []
    for y in 1..<7 {
      for x in 1..<7 where !(2...5 ~= x && 2...5 ~= y) {
        for channel in 0..<3 {
          var total = 0
          for py in (y * 4)..<(y * 4 + 4) {
            for px in (x * 4)..<(x * 4 + 4) {
              total += Int(pixels[(py * 32 + px) * 4 + channel])
            }
          }
          signature.append(Double(total) / 16)
        }
      }
    }
    guard let lo = signature.min(), let hi = signature.max(), hi - lo >= 35 else { return nil }
    return signature
  }

  static func videoMatches(_ left: CGImage, _ right: CGImage) -> Bool {
    let ratioA = Double(left.width) / Double(max(left.height, 1))
    let ratioB = Double(right.width) / Double(max(right.height, 1))
    guard abs(log(ratioA / ratioB)) <= 0.12,
          let a = videoSignature(left), let b = videoSignature(right), a.count == b.count else { return false }
    let differences = zip(a, b).map { abs($0 - $1) }
    return differences.reduce(0, +) / Double(a.count) <= 12 &&
      differences.filter { $0 > 35 }.count <= 2
  }

  /// Isolate a single photographic preview from an over-wide OCR crop. Text,
  /// watermarks and blank chat background must not enter cache comparisons.
  /// Missing or multiple substantial bands are deliberately unresolved.
  static func mediaPreviewCrop(_ image: CGImage) -> CGImage? {
    let scale = min(1, 384 / Double(max(image.width, image.height)))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    guard width >= 60, height >= 60,
          let pixels = rgbaPixels(image, width: width, height: height) else { return nil }
    func dark(_ x: Int, _ y: Int) -> Bool {
      let p = (y * width + x) * 4
      return min(pixels[p], pixels[p + 1], pixels[p + 2]) < 215
    }
    let rows = (0..<height).map { y in
      (0..<width).filter { dark($0, y) }.count >= Int(Double(width) * 0.45)
    }
    var bands: [Range<Int>] = []
    var start: Int?
    var last = 0
    let gap = max(2, height / 100)
    for y in 0..<height {
      if rows[y] {
        if start == nil { start = y }
        last = y
      } else if let beginning = start, y - last > gap {
        if last + 1 - beginning >= 60 { bands.append(beginning..<(last + 1)) }
        start = nil
      }
    }
    if let beginning = start, last + 1 - beginning >= 60 {
      bands.append(beginning..<(last + 1))
    }
    guard bands.count == 1, let band = bands.first else { return nil }
    let columns = (0..<width).filter { x in
      band.filter { dark(x, $0) }.count >= Int(Double(band.count) * 0.45)
    }
    guard let left = columns.first, let right = columns.last,
          right - left >= Int(Double(width) * 0.55) else { return nil }
    let bounds = CGRect(x: Double(left) / scale, y: Double(band.lowerBound) / scale,
                        width: Double(right - left + 1) / scale,
                        height: Double(band.count) / scale).integral
      .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return image.cropping(to: bounds)
  }

  /// JD can stretch a portrait clip's preview into a square card. Compare
  /// detailed colour evidence after isolating that card, not aspect ratios of
  /// the surrounding chat crop. The caller must still reject different clips
  /// that match, and independently verify the exact active customer.
  static func cachedVideoPreviewMatches(_ visible: CGImage, _ frame: CGImage) -> Bool {
    if videoMatches(visible, frame) { return true }
    guard let preview = mediaPreviewCrop(visible),
          let a = videoSignature(preview) else { return false }
    // A viewport can clip the top/bottom of a portrait card. Require at least
    // 70% of the original frame: a tiny matching patch is not ownership proof.
    for top in stride(from: 0.0, through: 0.30, by: 0.025) {
      for bottom in stride(from: 0.0, through: 0.30 - top, by: 0.025) {
        let bounds = CGRect(x: 0, y: CGFloat(frame.height) * CGFloat(top),
                            width: CGFloat(frame.width),
                            height: CGFloat(frame.height) * CGFloat(1 - top - bottom)).integral
        guard let part = frame.cropping(to: bounds),
          let b = videoSignature(part) else { continue }
        let differences = zip(a, b).map { abs($0 - $1) }
        if differences.reduce(0, +) / Double(a.count) <= 8 &&
            differences.filter({ $0 > 24 }).count <= 2 { return true }
      }
    }
    return false
  }

  /// Find the outlined circular play control throughout the supplied crop,
  /// including a thumbnail displaced by clipping or neighboring text. Both
  /// the circle and triangle need contrasting background; white paper alone
  /// must never count as a play button.
  static func hasVideoPlayControl(_ image: CGImage) -> Bool {
    let scale = min(1, 512 / Double(max(image.width, image.height)))
    let width = max(1, Int(Double(image.width) * scale))
    let height = max(1, Int(Double(image.height) * scale))
    guard min(width, height) >= 80,
          let pixels = rgbaPixels(image, width: width, height: height) else { return false }
    func brightness(_ x: Double, _ y: Double) -> Double {
      let px = Int(x.rounded()), py = Int(y.rounded())
      guard px >= 0, px < width, py >= 0, py < height else { return 0 }
      let p = (py * width + px) * 4
      return (0.2126 * Double(pixels[p]) + 0.7152 * Double(pixels[p + 1]) +
              0.0722 * Double(pixels[p + 2])) / 255
    }
    let shortest = Double(min(width, height))
    let step = max(3, Int(shortest * 0.012))
    for radius in stride(from: max(12, shortest * 0.055), through: shortest * 0.13, by: 2) {
      for y in stride(from: Int(radius), to: height - Int(radius), by: step) {
        for x in stride(from: Int(radius), to: width - Int(radius), by: step) {
          let cx = Double(x), cy = Double(y)
          guard brightness(cx, cy) >= 0.82,
                brightness(cx + radius * 0.25, cy) >= 0.82 else { continue }
          let corners = [(-0.35, -0.5), (0.4, -0.45), (0.4, 0.45)]
            .filter { brightness(cx + radius * $0.0, cy + radius * $0.1) < 0.78 }.count
          guard corners >= 2 else { continue }
          var ring = 0, outside = 0
          for sector in 0..<24 {
            let angle = Double(sector) * 2 * Double.pi / 24
            let c = cos(angle), s = sin(angle)
            if (-2...2).contains(where: { offset in
              brightness(cx + c * (radius + Double(offset)),
                         cy + s * (radius + Double(offset))) >= 0.85
            }) { ring += 1 }
            if brightness(cx + c * (radius + 6), cy + s * (radius + 6)) < 0.8 { outside += 1 }
          }
          if ring >= 20 && outside >= 15 { return true }
        }
      }
    }
    return false
  }

  private static func rgbaPixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
      guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
          bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
            CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? pixels : nil
  }
}
