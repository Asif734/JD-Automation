import Foundation
import CoreGraphics
import ImageIO
import AVFoundation

@main
struct CustomerSafetyCheck {
  static func main() throws {
    let ids = ["jd_6c67c99371fa4", "jd_frqocwtljjob", "格志打印机贝贝",
               "jd_vpliogabtzoy", "上海世亦小关", "jd_41aeec7741d05"]
    var checks = 0
    func verify(_ passed: Bool, _ message: String) {
      precondition(passed, message)
      checks += 1
    }
    for a in ids { for b in ids {
      verify(CustomerSafety.matches(a, b) == (a == b), "Cross-customer identity accepted")
      if a != b { verify(CustomerSafety.uniqueIdentity([a, b]) == nil, "Conflicting header accepted") }
    } }
    for bad in ["jd_4laeec7741d05", "JD_41AEEC7741D05", "jd_41aeec7741d0S", "jd_41aee…", "jd_41aee...", ""] {
      verify(!CustomerSafety.matches(bad, ids.last!), "Lookalike or prefix accepted")
    }
    verify(CustomerSafety.uniqueIdentity(["jd_41aee…"]) == nil, "Truncated identity accepted")
    verify(!CustomerSafety.matches(nil, nil), "Missing identity accepted")
    verify(!CustomerSafety.matches("caf\u{00e9}", "cafe\u{0301}"), "Different ID bytes merged by Unicode normalization")
    verify(CustomerSafety.uniqueIdentity(["caf\u{00e9}", "cafe\u{0301}"]) == nil, "Unicode ID ambiguity accepted")
    let clock = Date(timeIntervalSince1970: 100)
    verify(!CustomerSafety.operationCurrent(clock, now: clock), "Expired operation accepted")
    verify(CustomerSafety.operationCurrent(clock.addingTimeInterval(1), now: clock), "Current operation rejected")
    verify(!CustomerSafety.matches("Unknown customer", "Unknown customer"), "Unknown identity accepted")
    verify(CustomerSafety.canReconcileSidebarOCR(
      "jd_4laeec7741d05", verifiedAX: "jd_41aeec7741d05"),
      "A unique 1/l AX correction was rejected")
    verify(CustomerSafety.canReconcileSidebarOCR(
      "jd_frqocwtljob", verifiedAX: "jd_frqocwtljjob"),
      "A one-character AX insertion correction was rejected")
    verify(!CustomerSafety.canReconcileSidebarOCR(
      "上海世亦小关", verifiedAX: "上海世亦小闭"),
      "A non-JD identity was fuzzily redirected")
    verify(!CustomerSafety.canReconcileSidebarOCR(
      "jd_4laeec7741d05", verifiedAX: "jd_unrelated123"),
      "An unrelated AX identity was accepted")
    verify(CustomerSafety.uniqueVideoDigest(["same", "same"]) == "same", "Identical MP4 copies treated as different clips")
    verify(CustomerSafety.uniqueVideoDigest(["first", "second"]) == nil, "Different matching clips did not remain ambiguous")
    verify(CustomerSafety.uniqueVideoDigest([]) == nil, "Empty cache check accepted")
    verify(CustomerSafety.uniqueVideoDigest([""]) == nil, "Missing MP4 digest accepted")
    // Exact AX geometry from JD 10.4.5.600 on 2026-10-13. The previous selector
    // incorrectly treated both labels in the first 70 points as customer IDs.
    let chatFrame = CGRect(x: 346, y: 129, width: 511, height: 763)
    let customerFrame = CGRect(x: 408, y: 135, width: 120, height: 18)
    let shopFrame = CGRect(x: 742, y: 136, width: 105, height: 16)
    let transferFrame = CGRect(x: 408, y: 159, width: 16, height: 16)
    let shop = CustomerSafety.HeaderLabel(text: "grozziie格志专卖店", frame: shopFrame)
    func selected(_ labels: [CustomerSafety.HeaderLabel],
                  anchors: [CGRect]? = nil,
                  bounds: CGRect? = nil) -> String? {
      CustomerSafety.activeHeaderIdentity(labels: labels, chatFrame: bounds ?? chatFrame,
                                           quickTransferFrames: anchors ?? [transferFrame])
    }
    for owner in ids {
      let label = CustomerSafety.HeaderLabel(text: owner, frame: customerFrame)
      verify(selected([label, shop]) == owner, "Shop header blocked the correct customer")
      verify(selected([shop, label]) == owner, "AX enumeration order redirected customer selection")
      for other in ids {
        verify(CustomerSafety.matches(selected([label, shop]), other) == (owner == other),
               "Header verification accepted another customer")
      }
    }
    verify(selected([shop]) == nil, "Shop-only header was accepted as a customer")
    let label = CustomerSafety.HeaderLabel(text: ids.last!, frame: customerFrame)
    verify(selected([label, shop], anchors: []) == nil, "Header accepted without customer control anchor")
    verify(selected([label, shop], anchors: [transferFrame, transferFrame]) == nil,
           "Ambiguous customer control anchors accepted")
    let conflicting = CustomerSafety.HeaderLabel(text: ids.first!, frame: customerFrame)
    verify(selected([label, conflicting, shop]) == nil, "Conflicting customer-slot IDs accepted")
    let truncated = CustomerSafety.HeaderLabel(text: "jd_41aee…", frame: customerFrame)
    verify(selected([truncated, shop]) == nil, "Truncated customer header accepted")
    verify(selected([label, truncated, shop]) == nil, "Incomplete conflicting header ignored")
    verify(selected([label, label, shop]) == ids.last!, "Identical customer evidence rejected")
    let invalid = CustomerSafety.HeaderLabel(text: "unknown", frame: customerFrame)
    verify(selected([invalid, shop]) == nil, "Unknown customer header accepted")
    let message = CustomerSafety.HeaderLabel(text: ids.first!,
        frame: CGRect(x: 408, y: 235, width: 120, height: 18))
    verify(selected([label, message, shop]) == ids.last!, "Transcript message became header identity")
    let sidebar = CustomerSafety.HeaderLabel(text: ids.first!,
        frame: CGRect(x: 114, y: 135, width: 120, height: 18))
    verify(selected([label, sidebar, shop]) == ids.last!, "Sidebar identity became active identity")
    let shopNamedCustomer = CustomerSafety.HeaderLabel(text: shop.text, frame: customerFrame)
    verify(selected([shopNamedCustomer, shop]) == shop.text, "Shop-name blacklist replaced geometric customer proof")
    for scale: CGFloat in [0.5, 1, 2] {
      func moved(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX * scale - 1400, y: r.minY * scale + 500,
               width: r.width * scale, height: r.height * scale)
      }
      verify(selected([
        CustomerSafety.HeaderLabel(text: ids.last!, frame: moved(customerFrame)),
        CustomerSafety.HeaderLabel(text: shop.text, frame: moved(shopFrame)),
      ], anchors: [moved(transferFrame)], bounds: moved(chatFrame)) == ids.last!,
             "Scaled/moved JD window broke customer header selection")
    }
    for owner in ids { for active in ids {
      verify(CustomerSafety.canRecoverOwnedComposer(owner: owner, active: active,
        insertedText: "owned reply", currentText: "owned reply", sameElement: true) == (owner == active),
        "Composer recovery crossed customer ownership")
    } }
    verify(!CustomerSafety.canRecoverOwnedComposer(owner: ids[0], active: ids[0],
      insertedText: "owned reply", currentText: "operator edit", sameElement: true), "Operator text erased")
    verify(!CustomerSafety.canRecoverOwnedComposer(owner: ids[0], active: ids[0],
      insertedText: "owned reply", currentText: "owned reply", sameElement: false), "Stale composer erased")
    verify(!CustomerSafety.canRecoverOwnedComposer(owner: ids[0], active: nil,
      insertedText: "owned reply", currentText: "owned reply", sameElement: true), "Unknown composer owner accepted")
    let outer = AccessibilityBudget(deadline: Date().addingTimeInterval(10))
    verify(outer.isCurrent, "Fresh AX budget rejected")
    let expired = AccessibilityBudget(deadline: Date().addingTimeInterval(-1))
    verify(!expired.isCurrent, "Expired AX budget accepted")
    expired.invalidate()
    expired.close()
    verify(AccessibilityBudget.current === outer, "AX budget did not restore parent")
    verify(!outer.isCurrent, "Timed-out child AX snapshot did not invalidate operation")
    outer.close()
    verify(AccessibilityBudget.current == nil, "AX budget leaked into next operation")
    let fresh = AccessibilityBudget(deadline: Date().addingTimeInterval(10))
    verify(fresh.isCurrent, "Failed AX request poisoned unrelated later request")
    fresh.close()
    let expiredQueueItem = AccessibilityBudget(deadline: Date().addingTimeInterval(3600),
      uptimeDeadline: ProcessInfo.processInfo.systemUptime - 1)
    verify(!expiredQueueItem.isCurrent, "Wall-clock change revived an expired native queue item")
    expiredQueueItem.close()
    if let project = ProcessInfo.processInfo.environment["JD_REPLAY_PROJECT"] {
      func image(_ path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: project).appendingPathComponent(path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
          throw NSError(domain: "missing_replay_frame", code: 1)
        }
        return image
      }
      let windows = try image("data/media/jd_6c67c99371fa4/videos/frames_62bffbb019f1ada0/frame_01.jpg")
      let m880 = try image("data/media/jd_6c67c99371fa4/videos/frames_f84d688641ffed13/frame_13.jpg")
      verify(CustomerSafety.videoMatches(windows, windows), "Identical Windows frame rejected")
      verify(CustomerSafety.videoMatches(m880, m880), "Identical M880 frame rejected")
      verify(!CustomerSafety.videoMatches(windows, m880), "Yesterday's unrelated Windows video accepted for M880")
      let printer = try image("data/media/jd_41aeec7741d05/videos/frames_a9e0db5e199199d6/frame_01.jpg")
      let clip = AVAssetImageGenerator(asset: AVURLAsset(url: URL(fileURLWithPath: project)
        .appendingPathComponent("data/media/jd_41aeec7741d05/videos/9aaf6ed0d1e44ba595401291b9a73dc8.mp4")))
      clip.appliesPreferredTrackTransform = true
      clip.maximumSize = CGSize(width: 360, height: 360)
      let clipFrames = try [0.0, 0.5, 1.0].map {
        try clip.copyCGImage(at: CMTime(seconds: $0, preferredTimescale: 600), actualTime: nil)
      }
      for path in ["data/media/jd_41aeec7741d05/9a954a8e6ccc1185.png",
                   "data/media/jd_41aeec7741d05/1384b39b2d7467b6.png"] {
        let preview = try image(path)
        verify(CustomerSafety.hasVideoPlayControl(preview), "Off-center customer video classified as image")
        verify(!CustomerSafety.cachedVideoPreviewMatches(preview, windows), "Printer preview accepted unrelated Windows clip")
        verify(!CustomerSafety.cachedVideoPreviewMatches(preview, m880), "Printer preview accepted unrelated M880 clip")
        let matched = clipFrames.contains { CustomerSafety.cachedVideoPreviewMatches(preview, $0) }
        verify(matched == (preview.height == 454),
               "Cache cross-check must recover the complete preview but reject insufficient clipped-frame evidence")
      }
      verify(!CustomerSafety.hasVideoPlayControl(windows), "Windows screenshot classified as video")
      verify(!CustomerSafety.hasVideoPlayControl(m880), "M880 frame classified as video")
      verify(!CustomerSafety.hasVideoPlayControl(printer), "Printer frame without play button classified as video")
      verify(CustomerSafety.cachedVideoPreviewMatches(printer, printer), "Cache cross-check cannot recover video when its play overlay is absent")
      let bitmap = CGContext(data: nil, width: 360, height: 454, bitsPerComponent: 8,
        bytesPerRow: 360 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      for grey in [0.3, 1.0] {
        bitmap.setFillColor(CGColor(gray: grey, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: 360, height: 454))
        let flat = bitmap.makeImage()!
        verify(!CustomerSafety.hasVideoPlayControl(flat), "Flat background mistaken for a play control")
        verify(!CustomerSafety.cachedVideoPreviewMatches(flat, printer), "Flat placeholder assigned to cached printer clip")
      }
    }
    print("Native customer/video safety: \(checks) checks passed; no UI operations or sends.")
  }
}
