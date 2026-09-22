import ApplicationServices
import Cocoa
import CryptoKit
import FlutterMacOS
import Speech
import Vision

/// MethodChannel boundary for the macOS-only adapter. No send/insert/confirm action is exposed.
final class AccessibilityBridge {
  private let channel: FlutterMethodChannel
  private let collector = QianniuAXCollector()
  private let ocrInspector = QianniuOCRInspector()
  private let audioTranscriber = VideoAudioTranscriber()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.grozziie.jdAutomation/accessibility",
      binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    collector.onCapture = { [weak self] capture in
      DispatchQueue.main.async { self?.channel.invokeMethod("capture", arguments: capture) }
    }
    collector.onDiagnostic = { [weak self] diagnostic in
      DispatchQueue.main.async { self?.channel.invokeMethod("diagnostic", arguments: diagnostic) }
    }
    ocrInspector.customerIdentityProvider = { [weak collector] in
      collector?.activeCustomerIdentity()
    }
    ocrInspector.chatFrameProvider = { [weak collector] in
      collector?.activeChatFrame()
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status": result(collector.status())
    case "requestAccessibility": result(collector.requestAccessibility())
    case "requestScreenRecording": result(ocrInspector.requestScreenRecording())
    case "listOCRWindows": result(ocrInspector.availableWindows())
    case "inspectOCR":
      let args = call.arguments as? [String: Any]
      let requestedWindowID = (args?["windowId"] as? NSNumber)
        .map { CGWindowID($0.uint32Value) }
      ocrInspector.inspect(
        windowID: requestedWindowID,
        recognitionLevel: args?["recognitionLevel"] as? String ?? "accurate",
        completion: result)
    case "captureImageRegion":
      let args = call.arguments as? [String: Any]
      collector.captureImageRegion(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        windowID: CGWindowID((args?["windowId"] as? NSNumber)?.uint32Value ?? 0),
        normalizedX: (args?["x"] as? NSNumber)?.doubleValue ?? -1,
        normalizedY: (args?["y"] as? NSNumber)?.doubleValue ?? -1,
        normalizedWidth: (args?["width"] as? NSNumber)?.doubleValue ?? -1,
        normalizedHeight: (args?["height"] as? NSNumber)?.doubleValue ?? -1,
        allowActivationForVideoDetection:
          args?["allowActivationForVideoDetection"] as? Bool ?? false,
        completion: result)
    case "classifyMessageAt":
      let args = call.arguments as? [String: Any]
      collector.classifyMessageAt(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        windowID: CGWindowID((args?["windowId"] as? NSNumber)?.uint32Value ?? 0),
        normalizedX: (args?["x"] as? NSNumber)?.doubleValue ?? -1,
        normalizedY: (args?["y"] as? NSNumber)?.doubleValue ?? -1,
        completion: result)
    case "downloadImageAt":
      let args = call.arguments as? [String: Any]
      collector.downloadImageAt(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        windowID: CGWindowID((args?["windowId"] as? NSNumber)?.uint32Value ?? 0),
        normalizedX: (args?["x"] as? NSNumber)?.doubleValue ?? -1,
        normalizedY: (args?["y"] as? NSNumber)?.doubleValue ?? -1,
        completion: result)
    case "downloadVideoAt":
      let args = call.arguments as? [String: Any]
      collector.downloadVideoAt(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        windowID: CGWindowID((args?["windowId"] as? NSNumber)?.uint32Value ?? 0),
        normalizedX: (args?["x"] as? NSNumber)?.doubleValue ?? -1,
        normalizedY: (args?["y"] as? NSNumber)?.doubleValue ?? -1,
        normalizedWidth: (args?["width"] as? NSNumber)?.doubleValue ?? -1,
        normalizedHeight: (args?["height"] as? NSNumber)?.doubleValue ?? -1,
        destinationDirectory: args?["destinationDirectory"] as? String ?? "",
        completion: result)
    case "transcribeAudio":
      let args = call.arguments as? [String: Any]
      audioTranscriber.transcribe(
        path: args?["path"] as? String ?? "", completion: result)
    case "sendDraftOnce":
      let args = call.arguments as? [String: Any]
      collector.sendDraftOnce(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        reply: args?["reply"] as? String ?? "",
        mediaPaths: args?["mediaPaths"] as? [String] ?? [],
        completion: result)
    case "startCapture":
      collector.start(); result(nil)
    case "stopCapture":
      collector.stop(); result(nil)
    case "inspectTree":
      let args = call.arguments as? [String: Any]
      result(collector.inspectTree(maxDepth: args?["maxDepth"] as? Int ?? 12))
    case "listConversations":
      result(collector.conversationIdentities())
    case "listConversationRows":
      result(collector.conversationRows())
    case "ensureReceptionWindow":
      let args = call.arguments as? [String: Any]
      collector.ensureReceptionWindow(
        allowActivation: args?["allowActivation"] as? Bool ?? true,
        completion: result)
    case "openConversation":
      let args = call.arguments as? [String: Any]
      collector.openConversation(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        allowActivation: args?["allowActivation"] as? Bool ?? true,
        completion: result)
    case "scrollConversation":
      let args = call.arguments as? [String: Any]
      collector.scrollConversation(
        expectedCustomer: args?["expectedCustomer"] as? String ?? "",
        deltaY: (args?["deltaY"] as? NSNumber)?.int32Value ?? 0,
        completion: result)
    default: result(FlutterMethodNotImplemented)
    }
  }
}

/// Transcribes a local speech-ready WAV with macOS Speech. Chinese and English
/// are evaluated independently and the higher-confidence non-empty result is
/// returned. This API never records from the microphone.
final class VideoAudioTranscriber {
  private struct Candidate {
    let transcript: String
    let language: String
    let confidence: Double
  }

  func transcribe(path: String, completion: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    guard !path.isEmpty, FileManager.default.fileExists(atPath: url.path) else {
      completion(["error": "audio_missing",
                  "message": "The extracted video audio file is missing."])
      return
    }
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        DispatchQueue.main.async {
          completion(["error": "speech_recognition_not_allowed",
                      "message": "Speech Recognition permission is required to transcribe video audio."])
        }
        return
      }
      self.recognize(url: url, languages: ["zh-CN", "en-US"],
                     candidates: [], completion: completion)
    }
  }

  private func recognize(url: URL, languages: [String],
                         candidates: [Candidate],
                         completion: @escaping FlutterResult) {
    guard let language = languages.first else {
      let best = candidates.max { left, right in
        if left.confidence == right.confidence {
          return left.transcript.count < right.transcript.count
        }
        return left.confidence < right.confidence
      }
      DispatchQueue.main.async {
        completion([
          "transcript": best?.transcript ?? "",
          "language": best?.language ?? "",
          "confidence": best?.confidence ?? 0,
          "speechDetected": best?.transcript.isEmpty == false,
        ])
      }
      return
    }
    let remaining = Array(languages.dropFirst())
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)),
          recognizer.isAvailable else {
      recognize(url: url, languages: remaining, candidates: candidates,
                completion: completion)
      return
    }
    let request = SFSpeechURLRecognitionRequest(url: url)
    request.shouldReportPartialResults = false
    var finished = false
    recognizer.recognitionTask(with: request) { result, error in
      guard !finished else { return }
      if let result, result.isFinal {
        finished = true
        let transcript = result.bestTranscription.formattedString
          .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = result.bestTranscription.segments
        let confidence = segments.isEmpty ? 0 :
          segments.reduce(0) { $0 + Double($1.confidence) } /
            Double(segments.count)
        let next = transcript.isEmpty ? candidates : candidates + [Candidate(
          transcript: transcript, language: language, confidence: confidence)]
        self.recognize(url: url, languages: remaining, candidates: next,
                       completion: completion)
      } else if error != nil {
        finished = true
        self.recognize(url: url, languages: remaining,
                       candidates: candidates, completion: completion)
      }
    }
  }
}

/// Window-only screenshot and Apple Vision diagnostics. This inspector never
/// clicks, types, inserts, or sends anything to Qianniu.
final class QianniuOCRInspector {
  var customerIdentityProvider: (() -> String?)?
  var chatFrameProvider: (() -> CGRect?)?
  private let bundleIdentifier = "com.jd.jdmddwb"
  private let queue = DispatchQueue(label: "jd.ocr.inspect", qos: .userInitiated)

  func requestScreenRecording() -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    return CGRequestScreenCaptureAccess()
  }

  func availableWindows() -> [[String: Any]] {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .first(where: { !$0.isTerminated })?.processIdentifier else { return [] }
    return windows(pid: pid).map(\.payload)
  }

  func inspect(windowID: CGWindowID?, recognitionLevel: String, completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      let response: [String: Any]
      do {
        response = try self.captureAndRecognize(
          windowID: windowID,
          recognitionLevel: recognitionLevel)
      } catch let error as OCRInspectorError {
        response = error.payload
      } catch {
        response = ["error": "ocr_failed", "message": error.localizedDescription]
      }
      DispatchQueue.main.async { completion(response) }
    }
  }

  private func captureAndRecognize(windowID: CGWindowID?, recognitionLevel: String) throws -> [String: Any] {
    guard CGPreflightScreenCaptureAccess() else {
      throw OCRInspectorError(
        code: "screen_recording_not_allowed",
        message: "Grant Screen Recording permission to JD Automation, then restart the app.")
    }
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .first(where: { !$0.isTerminated }) else {
      throw OCRInspectorError(code: "jd_not_running", message: "JD 咚咚工作台 is not running.")
    }
    let availableWindows = windows(pid: app.processIdentifier)
    guard let window = windowID.flatMap({ selectedID in
      availableWindows.first(where: { $0.id == selectedID })
    }) ?? availableWindows.max(by: { $0.area < $1.area }) else {
      throw OCRInspectorError(
        code: "jd_window_missing",
        message: "No visible JD 咚咚 window was found. Open its customer-service window and retry.")
    }
    let customerBeforeCapture = customerIdentityProvider?()
    guard let image = CGWindowListCreateImage(
      .null,
      .optionIncludingWindow,
      window.id,
      [.boundsIgnoreFraming, .bestResolution]) else {
      throw OCRInspectorError(code: "window_capture_failed", message: "macOS could not capture the JD 咚咚 window.")
    }

    var observations: [[String: Any]] = []
    var visualRegions: [[String: Any]] = []
    let request = VNRecognizeTextRequest()
      request.recognitionLevel = recognitionLevel == "fast" ? .fast : .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

      // A second English pass recovers short wrapped lines that the mixed
      // language pass can omit. The shared Dart extractor then joins every
      // sender-bounded line using the recent workflow.
      let englishRequest = VNRecognizeTextRequest()
      englishRequest.recognitionLevel = request.recognitionLevel
      englishRequest.usesLanguageCorrection = false
      englishRequest.recognitionLanguages = ["en-US"]

      // Use an independent Chinese pass so a short Chinese bubble cannot be
      // reduced to a Latin placeholder such as `D` by the mixed pass.
      let chineseRequest = VNRecognizeTextRequest()
      chineseRequest.recognitionLevel = request.recognitionLevel
      chineseRequest.usesLanguageCorrection = false
      chineseRequest.recognitionLanguages = ["zh-Hans", "zh-Hant"]

      let rectangles = VNDetectRectanglesRequest()
      rectangles.maximumObservations = 24
      rectangles.minimumSize = 0.06
      rectangles.minimumAspectRatio = 0.25
      rectangles.maximumAspectRatio = 4.0
      rectangles.quadratureTolerance = 18
      try VNImageRequestHandler(cgImage: image, orientation: .up)
        .perform([request, englishRequest, chineseRequest, rectangles])

      struct RecognizedLine {
        let text: String
        let confidence: Float
        let box: CGRect
      }
      func lines(from results: [VNRecognizedTextObservation]?) -> [RecognizedLine] {
        (results ?? []).compactMap { observation in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          return RecognizedLine(
            text: candidate.string,
            confidence: candidate.confidence,
            box: observation.boundingBox)
        }
      }
      func sameVisualLine(_ left: CGRect, _ right: CGRect) -> Bool {
        let intersection = left.intersection(right)
        guard !intersection.isNull else { return false }
        let smallerArea = min(left.width * left.height, right.width * right.height)
        return smallerArea > 0 && intersection.width * intersection.height / smallerArea >= 0.45
      }

      func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
          (0x3400...0x9FFF).contains(Int(scalar.value))
        }
      }

      var mergedLines = lines(from: request.results)
      func merge(_ fallbackLines: [RecognizedLine]) {
        for fallback in fallbackLines {
          if let index = mergedLines.firstIndex(where: { sameVisualLine($0.box, fallback.box) }) {
            let current = mergedLines[index]
            let currentHasHan = containsHan(current.text)
            let fallbackHasHan = containsHan(fallback.text)
            let currentLength = current.text.replacingOccurrences(of: " ", with: "").count
            let fallbackLength = fallback.text.replacingOccurrences(of: " ", with: "").count
            if (fallbackHasHan && !currentHasHan) ||
                (fallbackHasHan == currentHasHan &&
                  (fallbackLength > currentLength ||
                    (fallbackLength == currentLength && fallback.confidence > current.confidence))) {
              mergedLines[index] = fallback
            }
          } else {
            mergedLines.append(fallback)
          }
        }
      }
      merge(lines(from: englishRequest.results))
      merge(lines(from: chineseRequest.results))

      observations = mergedLines.map { line -> [String: Any] in
        let box = line.box
        return [
          "text": line.text,
          "confidence": Double(line.confidence),
          "x": Double(box.minX),
          "y": Double(1 - box.maxY),
          "width": Double(box.width),
          "height": Double(box.height),
        ]
      }.sorted {
        let leftY = $0["y"] as? Double ?? 0
        let rightY = $1["y"] as? Double ?? 0
        if abs(leftY - rightY) > 0.01 { return leftY < rightY }
        return ($0["x"] as? Double ?? 0) < ($1["x"] as? Double ?? 0)
      }
    visualRegions = (rectangles.results ?? []).map { observation -> [String: Any] in
        let box = observation.boundingBox
        return [
          "x": Double(box.minX),
          "y": Double(1 - box.maxY),
          "width": Double(box.width),
          "height": Double(box.height),
          "confidence": Double(observation.confidence),
        ]
    }

    guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
      throw OCRInspectorError(code: "png_encoding_failed", message: "Could not encode the captured window image.")
    }
    let customerAfterRecognition = customerIdentityProvider?()
    guard let customerBeforeCapture, let customerAfterRecognition,
          exactCustomerIdentityMatches(customerBeforeCapture, customerAfterRecognition) else {
      throw OCRInspectorError(code: "customer_changed_during_capture",
                              message: "The JD conversation changed during OCR; this screenshot was discarded.")
    }
    var payload: [String: Any] = [
      "pid": Int(app.processIdentifier),
      "windowId": Int(window.id),
      "windowTitle": window.title,
      "windowBounds": [
        "x": Double(window.bounds.minX), "y": Double(window.bounds.minY),
        "width": Double(window.bounds.width), "height": Double(window.bounds.height),
      ],
      "imageWidth": image.width,
      "imageHeight": image.height,
      "pngBase64": png.base64EncodedString(),
      "observations": observations,
      "visualRegions": visualRegions,
      "recognizedText": observations.compactMap { $0["text"] as? String }.joined(separator: "\n"),
      "ocrEngine": "apple_vision",
      "activeCustomerId": customerAfterRecognition,
      "capturedAtMs": Int(Date().timeIntervalSince1970 * 1000),
    ]
    if let chatFrame = chatFrameProvider?(), window.bounds.width > 0 {
      let left = max(0, min(1,
        (chatFrame.minX - window.bounds.minX) / window.bounds.width))
      let right = max(left, min(1,
        (chatFrame.maxX - window.bounds.minX) / window.bounds.width))
      payload["chatRegion"] = [
        "left": Double(left),
        "right": Double(right),
      ]
    }
    return payload
  }

  private func windows(pid: pid_t) -> [OCRWindow] {
    // CGWindowListCopyWindowInfo returns windows from front to back. Preserve
    // that order: Qianniu's detached reception window floats above its main UI.
    guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
      as? [[String: Any]] else { return [] }
    return raw.compactMap { info -> OCRWindow? in
      guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
            (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
            let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
            let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
            bounds.width >= 300, bounds.height >= 200 else { return nil }
      return OCRWindow(
        id: CGWindowID(id),
        title: info[kCGWindowName as String] as? String ?? "JD 咚咚工作台",
        bounds: bounds)
    }
  }
}

private struct OCRWindow {
  let id: CGWindowID
  let title: String
  let bounds: CGRect

  var area: CGFloat { bounds.width * bounds.height }

  var payload: [String: Any] {
    [
      "windowId": Int(id),
      "title": title,
      "x": Double(bounds.minX),
      "y": Double(bounds.minY),
      "width": Double(bounds.width),
      "height": Double(bounds.height),
    ]
  }
}

private struct UnreadScreenshot {
  let bounds: CGRect
  let image: CGImage
}

private struct DownloadedImageCandidate {
  let url: URL
  let modified: Date
  let size: Int
}

private struct DownloadedVideoCandidate {
  let url: URL
  let modified: Date
  let size: Int
}

private func downloadableImages(in directory: URL) -> [String: DownloadedImageCandidate] {
  let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
  guard let urls = try? FileManager.default.contentsOfDirectory(
    at: directory, includingPropertiesForKeys: Array(keys),
    options: [.skipsHiddenFiles]) else { return [:] }
  let extensions = Set(["jpg", "jpeg", "png", "webp", "heic", "gif"])
  var result: [String: DownloadedImageCandidate] = [:]
  for url in urls where extensions.contains(url.pathExtension.lowercased()) {
    guard let values = try? url.resourceValues(forKeys: keys),
          values.isRegularFile == true else { continue }
    result[url.path] = DownloadedImageCandidate(
      url: url,
      modified: values.contentModificationDate ?? .distantPast,
      size: values.fileSize ?? 0)
  }
  return result
}

/// JD 10.4 downloads an incoming video into its own per-chat media cache before
/// rendering the thumbnail. Restrict discovery to that cache shape and a short
/// freshness window so automatic analysis never needs to click inside JD.
private func newestRecentJDCachedVideo(
  now: Date = Date(), maximumAge: TimeInterval = 5 * 60
) -> DownloadedVideoCandidate? {
  let root = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/JingDong/咚咚工作台",
                           isDirectory: true)
  let keys: Set<URLResourceKey> = [
    .contentModificationDateKey, .fileSizeKey, .isRegularFileKey,
  ]
  guard let enumerator = FileManager.default.enumerator(
    at: root, includingPropertiesForKeys: Array(keys),
    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return nil }
  let extensions = Set(["mp4", "mov", "m4v", "webm"])
  var candidates: [DownloadedVideoCandidate] = []
  for case let url as URL in enumerator {
    let parent = url.deletingLastPathComponent()
    let chatDirectory = parent.deletingLastPathComponent().lastPathComponent
    guard parent.lastPathComponent == "videos",
          chatDirectory.hasPrefix("chat_"),
          extensions.contains(url.pathExtension.lowercased()),
          let values = try? url.resourceValues(forKeys: keys),
          values.isRegularFile == true,
          let modified = values.contentModificationDate,
          let size = values.fileSize,
          size > 0, size <= 100 * 1024 * 1024 else { continue }
    let age = now.timeIntervalSince(modified)
    guard age >= -5, age <= maximumAge else { continue }
    candidates.append(DownloadedVideoCandidate(
      url: url, modified: modified, size: size))
  }
  return candidates.max(by: { $0.modified < $1.modified })
}

private func windowBounds(_ id: CGWindowID) -> CGRect? {
  guard let raw = CGWindowListCopyWindowInfo(.optionIncludingWindow, id)
          as? [[String: Any]], let info = raw.first,
        let dictionary = info[kCGWindowBounds as String] as? [String: Any]
  else { return nil }
  return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
}

private func namedWindowBounds(pid: pid_t, containing title: String) -> CGRect? {
  guard let raw = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
          as? [[String: Any]] else { return nil }
  for info in raw where
    (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
    ((info[kCGWindowName as String] as? String)?.contains(title) == true) {
    guard let dictionary = info[kCGWindowBounds as String] as? [String: Any]
    else { continue }
    if let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) {
      return bounds
    }
  }
  return nil
}

private func unreadScreenshot(pid: pid_t) -> UnreadScreenshot? {
  guard CGPreflightScreenCaptureAccess(),
        let raw = CGWindowListCopyWindowInfo(
          [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
          as? [[String: Any]],
        let info = raw.first(where: {
          ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
          ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0 &&
          (($0[kCGWindowName as String] as? String)?.contains("咚咚融合工作台") == true)
        }),
        let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
        let dictionary = info[kCGWindowBounds as String] as? [String: Any],
        let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
        let image = CGWindowListCreateImage(
          .null, .optionIncludingWindow, CGWindowID(id),
          [.boundsIgnoreFraming, .bestResolution]) else { return nil }
  return UnreadScreenshot(bounds: bounds, image: image)
}

private func unreadRedPixels(frame: CGRect, windowBounds: CGRect,
                             image: CGImage) -> Int {
  guard windowBounds.width > 0, windowBounds.height > 0 else { return 0 }
  let scaleX = CGFloat(image.width) / windowBounds.width
  let scaleY = CGFloat(image.height) / windowBounds.height
  let localX = (frame.minX - windowBounds.minX + frame.width * 0.65) * scaleX
  let localY = (frame.minY - windowBounds.minY) * scaleY
  let width = frame.width * 0.35 * scaleX
  let height = frame.height * scaleY
  let bitmap = NSBitmapImageRep(cgImage: image)

  func count(in rect: CGRect) -> Int {
    let minX = max(0, Int(rect.minX))
    let maxX = min(image.width, Int(rect.maxX))
    let minY = max(0, Int(rect.minY))
    let maxY = min(image.height, Int(rect.maxY))
    guard minX < maxX, minY < maxY else { return 0 }
    var result = 0
    for y in stride(from: minY, to: maxY, by: 2) {
      for x in stride(from: minX, to: maxX, by: 2) {
        guard let color = bitmap.colorAt(x: x, y: y)?
                .usingColorSpace(.deviceRGB) else { continue }
        let red = Int(color.redComponent * 255)
        let green = Int(color.greenComponent * 255)
        let blue = Int(color.blueComponent * 255)
        if red >= 185 && green <= 125 && blue <= 125 && red >= green + 60 {
          result += 1
        }
      }
    }
    return result
  }
  let topOrigin = CGRect(x: localX, y: localY, width: width, height: height)
  let flipped = CGRect(x: localX, y: CGFloat(image.height) - localY - height,
                       width: width, height: height)
  return max(count(in: topOrigin), count(in: flipped))
}

private func normalizedCustomerIdentity(_ value: String) -> String {
  value.trimmingCharacters(in: .whitespacesAndNewlines)
    .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
}

private func exactCustomerIdentityMatches(_ left: String, _ right: String) -> Bool {
  normalizedCustomerIdentity(left) == normalizedCustomerIdentity(right)
}

private func visibleCustomerIdentityMatches(_ visible: String, expected: String) -> Bool {
  if exactCustomerIdentityMatches(visible, expected) { return true }
  let trimmed = visible.trimmingCharacters(in: .whitespacesAndNewlines)
  let isTruncated = trimmed.contains("...") || trimmed.contains("…")
  guard isTruncated else { return false }
  let prefix = normalizedCustomerIdentity(
    trimmed.replacingOccurrences(of: "...", with: "")
      .replacingOccurrences(of: "…", with: ""))
  // Truncated headers are useful only when they expose a meaningful prefix.
  // Three Unicode characters covers short CJK names; six is retained for
  // Latin/digit-only identities where a tiny prefix is too collision-prone.
  let latinOnly = prefix.unicodeScalars.allSatisfy { $0.isASCII }
  guard prefix.count >= (latinOnly ? 6 : 3) else { return false }
  return normalizedCustomerIdentity(expected).hasPrefix(prefix)
}

private func cleanedRowCustomerIdentity(_ raw: String) -> String? {
  var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
  text = text.replacingOccurrences(
    of: #"\s+(?:20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}\s+)?\d{1,2}:\d{2}(?::\d{2})?\s*$"#,
    with: "", options: .regularExpression)
    .trimmingCharacters(in: .whitespacesAndNewlines)
  guard !text.isEmpty, text.count <= 80,
        !text.contains("..."), !text.contains("…"),
        text.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
  let compact = text.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
  let ignored: Set<String> = [
    "在线咨询", "留言", "排序", "清除", "紧凑布局", "客服助手", "暂无选中的会话",
  ]
  guard !ignored.contains(compact),
        text.range(of: #"^\d{1,2}:\d{2}(?::\d{2})?$"#,
                   options: .regularExpression) == nil else { return nil }
  return text
}

/// JD exposes each conversation as an untitled pressable AXGroup. Read the
/// first-line display identity from that group's screenshot crop; the active
/// header is still used independently after a click to verify the selection.
private func customerIDInRow(frame: CGRect, windowBounds: CGRect,
                             image: CGImage) -> String? {
  guard windowBounds.width > 0, windowBounds.height > 0 else { return nil }
  let scaleX = CGFloat(image.width) / windowBounds.width
  let scaleY = CGFloat(image.height) / windowBounds.height
  let x = (frame.minX - windowBounds.minX) * scaleX
  let y = (frame.minY - windowBounds.minY) * scaleY
  let width = frame.width * scaleX
  let height = frame.height * scaleY
  let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
  let candidates = [
    CGRect(x: x, y: y, width: width, height: height).integral.intersection(bounds),
    CGRect(x: x, y: CGFloat(image.height) - y - height,
           width: width, height: height).integral.intersection(bounds),
  ]
  for rect in candidates where rect.width >= 40 && rect.height >= 20 {
    guard let crop = image.cropping(to: rect) else { continue }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])
    let ranked = (request.results ?? []).compactMap { observation -> (String, Double)? in
      guard observation.boundingBox.midY >= 0.46,
            observation.boundingBox.minX >= 0.10,
            observation.boundingBox.minX < 0.84,
            let candidate = observation.topCandidates(1).first,
            let identity = cleanedRowCustomerIdentity(candidate.string) else { return nil }
      // Prefer the upper-left text line. This separates the identity from the
      // lower message preview and the right-aligned recency/timestamp label.
      let score = Double(observation.boundingBox.midY) * 100 -
        Double(observation.boundingBox.minX) * 20 + Double(candidate.confidence)
      return (identity, score)
    }.sorted { $0.1 > $1.1 }
    if let identity = ranked.first?.0 {
      return identity
    }
  }
  return nil
}

private struct OCRInspectorError: Error {
  let code: String
  let message: String

  var payload: [String: Any] { ["error": code, "message": message] }
}

private struct AXNode {
  let element: AXUIElement
  let path: String
  let role: String
  let subrole: String?
  let identifier: String?
  let title: String?
  let description: String?
  let value: String?
  let help: String?
  let frame: CGRect?
  let actions: [String]
  let children: [AXUIElement]

  var text: String? {
    [title, value, description].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }
}

/// AX discovery and conservative capture for com.taobao.Aliworkbench.
/// It uses structural traits only; install-specific labels must be learned from Inspect Tree output.
final class QianniuAXCollector {
  var onCapture: (([String: Any]) -> Void)?
  var onDiagnostic: (([String: Any]) -> Void)?

  private let bundleIdentifier = "com.jd.jdmddwb"
  private let queue = DispatchQueue(label: "jd.ax.capture", qos: .userInitiated)
  private var timer: DispatchSourceTimer?
  private var seenFingerprints = Set<String>()
  private var lastActiveConversation: String?

  func status() -> [String: Any] {
    let pid = runningPID()
    return [
      "trusted": AXIsProcessTrusted(),
      "running": pid != nil,
      "pid": pid.map(Int.init) as Any,
      "bundleIdentifier": bundleIdentifier,
      "captureRunning": timer != nil,
    ]
  }

  func requestAccessibility() -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }

  /// Captures a validated image-bubble region from the Qianniu window when its
  /// embedded web view does not expose image bytes through the pasteboard.
  func captureImageRegion(expectedCustomer: String, windowID: CGWindowID,
                          normalizedX: Double, normalizedY: Double,
                          normalizedWidth: Double, normalizedHeight: Double,
                          allowActivationForVideoDetection: Bool = false,
                          completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard AXIsProcessTrusted(), !expected.isEmpty,
            normalizedX >= 0, normalizedY >= 0,
            normalizedWidth > 0, normalizedHeight > 0,
            normalizedX + normalizedWidth <= 1,
            normalizedY + normalizedHeight <= 1,
            activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true else {
        finish(["error": "image_crop_precondition_failed",
                "message": "The expected customer or image region could not be verified."])
        return
      }
      guard let fullImage = CGWindowListCreateImage(
              .null, .optionIncludingWindow, windowID,
              [.boundsIgnoreFraming, .bestResolution]) else {
        finish(["error": "image_crop_window_failed",
                "message": "Could not capture the selected Qianniu window."])
        return
      }
      let crop = CGRect(
        x: CGFloat(normalizedX) * CGFloat(fullImage.width),
        y: CGFloat(normalizedY) * CGFloat(fullImage.height),
        width: CGFloat(normalizedWidth) * CGFloat(fullImage.width),
        height: CGFloat(normalizedHeight) * CGFloat(fullImage.height)).integral
      guard crop.width >= 40, crop.height >= 40,
            let image = fullImage.cropping(to: crop),
            activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true,
            let png = NSBitmapImageRep(cgImage: image)
              .representation(using: .png, properties: [:]) else {
        finish(["error": "image_crop_verification_failed",
                "message": "The image region or active customer changed during capture."])
        return
      }
      var videoDetected = looksLikeVideoThumbnail(image)
      // JD renders the play control in a separate overlay layer that is absent
      // from a window-only capture. When JD is frontmost, hover the verified
      // bubble and inspect a bounded composite crop solely for classification.
      let previouslyFrontmost = NSWorkspace.shared.frontmostApplication
      let jdPID = runningPID()
      var activatedForRetry = false
      if !videoDetected && allowActivationForVideoDetection,
         previouslyFrontmost?.processIdentifier != jdPID,
         let jdPID,
         let jdApp = NSRunningApplication(processIdentifier: jdPID) {
        activatedForRetry = jdApp.activate(options: [.activateIgnoringOtherApps])
        if activatedForRetry { usleep(200_000) }
      }
      defer {
        if activatedForRetry,
           let previous = previouslyFrontmost,
           !previous.isTerminated {
          _ = previous.activate(options: [.activateIgnoringOtherApps])
        }
      }
      if !videoDetected,
         NSWorkspace.shared.frontmostApplication?.processIdentifier == runningPID(),
         let bounds = windowBounds(windowID) {
        let screenCrop = CGRect(
          x: bounds.minX + bounds.width * normalizedX,
          y: bounds.minY + bounds.height * normalizedY,
          width: bounds.width * normalizedWidth,
          height: bounds.height * normalizedHeight).integral
        _ = postHover(at: CGPoint(x: screenCrop.midX, y: screenCrop.midY))
        if let composite = CGWindowListCreateImage(
             screenCrop, .optionOnScreenOnly, kCGNullWindowID,
             [.boundsIgnoreFraming, .bestResolution]) {
          videoDetected = looksLikeVideoThumbnail(composite)
        }
      }
      finish([
        "kind": videoDetected ? "video" : "image",
        "mimeType": "image/png",
        "extension": "png",
        "dataBase64": png.base64EncodedString(),
        "visualFingerprint": averageImageHash(image),
      ])
    }
  }

  /// Copies a freshly received video from JD's local per-chat media cache.
  /// AX and the sender-bounded OCR rectangle verify the active incoming bubble,
  /// but this method deliberately performs no clicks or keyboard actions in JD.
  func downloadVideoAt(expectedCustomer: String, windowID: CGWindowID,
                       normalizedX: Double, normalizedY: Double,
                       normalizedWidth: Double, normalizedHeight: Double,
                       destinationDirectory: String,
                       completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      let destination = URL(fileURLWithPath: destinationDirectory, isDirectory: true)
        .standardizedFileURL
      guard AXIsProcessTrusted(), !expected.isEmpty,
            normalizedX >= 0, normalizedY >= 0,
            normalizedWidth > 0, normalizedHeight > 0,
            normalizedX + normalizedWidth <= 1,
            normalizedY + normalizedHeight <= 1,
            activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true,
            runningPID() != nil, windowBounds(windowID) != nil,
            FileManager.default.fileExists(atPath: destination.path) else {
        finish(["error": "video_download_precondition_failed",
                "message": "Keep the verified customer video visible while its local cache is inspected."])
        return
      }
      guard let cached = newestRecentJDCachedVideo() else {
        finish(["error": "video_download_not_found",
                "message": "No fresh video was found in JD's local media cache; the conversation was left untouched."])
        return
      }
      var file = destination.appendingPathComponent(cached.url.lastPathComponent)
      if FileManager.default.fileExists(atPath: file.path) {
        file = destination.appendingPathComponent(
          "\(UUID().uuidString).\(cached.url.pathExtension)")
      }
      do {
        try FileManager.default.copyItem(at: cached.url, to: file)
      } catch {
        finish(["error": "video_copy_failed",
                "message": "JD's cached video could not be copied into private storage."])
        return
      }
      guard activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true,
            let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize, size == cached.size else {
        try? FileManager.default.removeItem(at: file)
        finish(["error": "video_copy_verification_failed",
                "message": "The cached video changed during copying; the partial copy was removed."])
        return
      }
      let ext = file.pathExtension.lowercased()
      let mime = ext == "mov" || ext == "m4v" ? "video/quicktime" :
        (ext == "webm" ? "video/webm" : "video/mp4")
      finish([
        "kind": "video",
        "path": file.path,
        "originalName": file.lastPathComponent,
        "mimeType": mime,
        "size": size,
        "captureSource": "jd-video-cache",
      ])
    }
  }

  /// Uses copy only to classify the selected Qianniu item. No clipboard
  /// content is returned and the user's previous clipboard is restored.
  func classifyMessageAt(expectedCustomer: String, windowID: CGWindowID,
                         normalizedX: Double, normalizedY: Double,
                         completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard AXIsProcessTrusted(), !expected.isEmpty,
            normalizedX >= 0, normalizedX <= 1,
            normalizedY >= 0, normalizedY <= 1,
            activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true,
            let pid = runningPID(),
            let jdApp = NSRunningApplication(processIdentifier: pid) else {
        finish(["kind": "unavailable", "reason": "qianniu_unavailable"])
        return
      }
      let previouslyFrontmost = NSWorkspace.shared.frontmostApplication
      let activatedForImageCheck = previouslyFrontmost?.processIdentifier != pid
      if activatedForImageCheck {
        _ = jdApp.activate(options: [.activateIgnoringOtherApps])
        usleep(300_000)
      }
      defer {
        if activatedForImageCheck,
           let previous = previouslyFrontmost,
           !previous.isTerminated {
          _ = previous.activate(options: [.activateIgnoringOtherApps])
        }
      }
      guard let raw = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID)
              as? [[String: Any]],
            let info = raw.first,
            let dictionary = info[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else {
        finish(["kind": "unavailable", "reason": "window_missing"])
        return
      }
      let pasteboard = NSPasteboard.general
      let snapshot = PasteboardSnapshot(pasteboard)
      defer { snapshot.restore(to: pasteboard) }
      pasteboard.clearContents()
      let point = CGPoint(x: bounds.minX + bounds.width * normalizedX,
                          y: bounds.minY + bounds.height * normalizedY)
      guard postClick(at: point), postCommandC() else {
        finish(["kind": "unavailable", "reason": "copy_failed"])
        return
      }
      usleep(300_000)
      let types = pasteboard.types ?? []
      let imageTypes: Set<NSPasteboard.PasteboardType> = [
        .png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), .fileURL,
      ]
      let kind: String
      var visualFingerprint = ""
      var copiedPNG: Data?
      if types.contains(where: { imageTypes.contains($0) }) {
        kind = "image"
        let imageData = pasteboard.data(forType: .png) ??
          pasteboard.data(forType: .tiff) ??
          pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
        if let imageData, let image = NSImage(data: imageData),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          visualFingerprint = averageImageHash(cgImage)
          copiedPNG = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:])
        } else if let fileURL = pasteboard.string(forType: .fileURL),
                  let url = URL(string: fileURL),
                  let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
          visualFingerprint = averageImageHash(cgImage)
          copiedPNG = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:])
        }
      } else if pasteboard.string(forType: .string) != nil {
        kind = "text"
      } else {
        kind = "unknown"
      }
      var payload: [String: Any] = [
        "kind": kind,
        "types": types.map(\.rawValue),
        "visualFingerprint": visualFingerprint,
      ]
      if let copiedPNG {
        payload["mimeType"] = "image/png"
        payload["extension"] = "png"
        payload["dataBase64"] = copiedPNG.base64EncodedString()
      }
      finish(payload)
    }
  }

  /// Opens a verified buyer image in JD's 图片浏览器 and downloads the original.
  /// Only a newly created image in Downloads is returned; the viewer is closed
  /// before the result crosses the Flutter boundary.
  func downloadImageAt(expectedCustomer: String, windowID: CGWindowID,
                       normalizedX: Double, normalizedY: Double,
                       completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard AXIsProcessTrusted(), !expected.isEmpty,
            normalizedX >= 0, normalizedX <= 1,
            normalizedY >= 0, normalizedY <= 1,
            activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true,
            let pid = runningPID(),
            NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
            let sourceBounds = windowBounds(windowID) else {
        finish(["error": "image_download_precondition_failed",
                "message": "The active customer, JD focus, or source window could not be verified."])
        return
      }
      let downloads = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)
      let before = downloadableImages(in: downloads)
      let sourcePoint = CGPoint(
        x: sourceBounds.minX + sourceBounds.width * normalizedX,
        y: sourceBounds.minY + sourceBounds.height * normalizedY)
      guard postDoubleClick(at: sourcePoint) else {
        finish(["error": "image_viewer_open_failed",
                "message": "Could not open the verified JD image bubble."])
        return
      }
      var viewer: CGRect?
      for _ in 0..<16 {
        usleep(125_000)
        viewer = namedWindowBounds(pid: pid, containing: "图片浏览器")
        if viewer != nil { break }
      }
      guard let viewerBounds = viewer else {
        finish(["error": "image_viewer_missing",
                "message": "JD did not expose its 图片浏览器 window."])
        return
      }
      var viewerClosed = false
      defer {
        if !viewerClosed {
          _ = closeJDImageViewer(pid: pid, bounds: viewerBounds)
        }
      }
      // In JD 9.95 the download control is the rightmost item in the centered
      // bottom toolbar. Keep this coordinate scoped to the verified viewer.
      let downloadPoint = CGPoint(
        x: viewerBounds.minX + viewerBounds.width * 0.590,
        y: viewerBounds.minY + viewerBounds.height * 0.944)
      guard postClick(at: downloadPoint) else {
        finish(["error": "image_download_click_failed",
                "message": "Could not press the JD image download control."])
        return
      }
      var downloaded: URL?
      // Keep JD's modal viewer open for no more than one second after the
      // download click. The Flutter layer falls back to a screenshot if the
      // original file does not become available within this bounded window.
      for _ in 0..<8 {
        usleep(125_000)
        let after = downloadableImages(in: downloads)
        downloaded = after.values
          .filter { candidate in
            guard let old = before[candidate.url.path] else { return true }
            return candidate.modified > old.modified || candidate.size != old.size
          }
          .sorted { $0.modified > $1.modified }
          .first?.url
        if downloaded != nil { break }
      }
      viewerClosed = closeJDImageViewer(pid: pid, bounds: viewerBounds)
      guard viewerClosed else {
        finish(["error": "image_viewer_close_failed",
                "message": "The JD image was captured, but 图片浏览器 could not be closed safely."])
        return
      }
      guard let file = downloaded,
            let data = try? Data(contentsOf: file),
            !data.isEmpty, data.count <= 25 * 1024 * 1024 else {
        finish(["error": "image_download_not_found",
                "message": "No new JD image appeared in Downloads."])
        return
      }
      let ext = file.pathExtension.lowercased()
      let mime = ext == "png" ? "image/png" :
        (ext == "webp" ? "image/webp" : "image/jpeg")
      let visualFingerprint: String
      if let image = NSImage(data: data),
         let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        visualFingerprint = averageImageHash(cgImage)
      } else {
        visualFingerprint = SHA256.hash(data: data).description
      }
      finish([
        "kind": "image",
        "mimeType": mime,
        "extension": ext.isEmpty ? "jpg" : ext,
        "originalName": file.lastPathComponent,
        "dataBase64": data.base64EncodedString(),
        "visualFingerprint": visualFingerprint,
        "captureSource": "jd-image-viewer-download",
      ])
    }
  }

  func start() {
    guard timer == nil else { return }
    let source = DispatchSource.makeTimerSource(queue: queue)
    source.schedule(deadline: .now(), repeating: .milliseconds(700), leeway: .milliseconds(150))
    source.setEventHandler { [weak self] in self?.poll() }
    timer = source
    source.resume()
  }

  func stop() {
    timer?.cancel()
    timer = nil
  }

  /// Performs one explicitly requested send. The expected conversation is
  /// opened and verified before insertion, then verified again before the
  /// physical Send control is clicked. No caller can omit the expected ID.
  func sendDraftOnce(expectedCustomer: String, reply: String,
                     mediaPaths: [String] = [],
                     completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !expected.isEmpty, !text.isEmpty else {
        finish(["error": "invalid_send_request", "message": "Expected customer and reply are required."])
        return
      }
      guard AXIsProcessTrusted(), let pid = runningPID() else {
        finish(["error": "jd_unavailable", "message": "JD 咚咚 or Accessibility access is unavailable."])
        return
      }
      guard mediaPaths.isEmpty else {
        finish(["error": "outbound_media_disabled",
                "message": "JD automation is text-only; photos, videos, and files are disabled."])
        return
      }
      let allowedExtensions = Set(["png", "jpg", "jpeg", "webp", "gif", "mp4", "mov"])
      let requestedMedia = Array(mediaPaths.prefix(3)).map {
        URL(fileURLWithPath: $0).standardizedFileURL
      }
      guard requestedMedia.count == mediaPaths.count,
            requestedMedia.allSatisfy({
              FileManager.default.fileExists(atPath: $0.path) &&
                allowedExtensions.contains($0.pathExtension.lowercased())
            }) else {
        finish(["error": "invalid_media_attachment",
                "message": "One or more approved media files are missing, unsupported, or exceed the three-file limit."])
        return
      }

      func scopedNodes() -> [AXNode]? {
        let root = AXUIElementCreateApplication(pid)
        var nodes: [AXNode] = []
        walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) { node, _ in nodes.append(node) }
        guard let window = nodes.first(where: {
          $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
        }) else { return nil }
        return nodes.filter { $0.path == window.path || $0.path.hasPrefix(window.path + "/") }
      }

      guard let initial = scopedNodes(), activeCustomerMatches(expected, nodes: initial) else {
        finish(["error": "expected_conversation_missing",
                "message": "The exact active JD customer \(expected) was not verified; nothing was inserted or sent."])
        return
      }

      guard let opened = scopedNodes(), activeCustomerMatches(expected, nodes: opened),
            let composer = opened.first(where: { $0.role == kAXTextAreaRole as String }) else {
        finish(["error": "pre_insert_verification_failed",
                "message": "Could not verify \(expected) and its composer after opening the chat."])
        return
      }
      let existing = stringAttribute(composer.element, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      guard existing.isEmpty else {
        finish(["error": "composer_not_empty",
                "message": "JD's composer already contains text. It was left unchanged."])
        return
      }
      if requestedMedia.isEmpty {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(composer.element, kAXValueAttribute as CFString, &settable) == .success,
              settable.boolValue,
              AXUIElementSetAttributeValue(composer.element, kAXValueAttribute as CFString, text as CFTypeRef) == .success else {
          finish(["error": "composer_not_settable",
                  "message": "Qianniu did not allow safe AX insertion; nothing was sent."])
          return
        }
      } else {
        // Qianniu's rich composer does not expose image insertion through AX.
        // Paste only caller-verified local files, then append the reply text.
        // Preserve the user's clipboard and verify the expected conversation
        // throughout the operation.
        _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        usleep(180_000)
        _ = AXUIElementSetAttributeValue(composer.element, kAXFocusedAttribute as CFString,
                                         kCFBooleanTrue)
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        defer { snapshot.restore(to: pasteboard) }
        let beforePaste = composerVisualFingerprint(pid: pid, frame: composer.frame)
        for mediaURL in requestedMedia {
          pasteboard.clearContents()
          let inserted: Bool
          if ["png", "jpg", "jpeg", "webp", "gif"].contains(mediaURL.pathExtension.lowercased()),
             let image = NSImage(contentsOf: mediaURL) {
            inserted = pasteboard.writeObjects([image])
          } else {
            inserted = pasteboard.writeObjects([mediaURL as NSURL])
          }
          guard inserted, postCommandV() else {
            finish(["error": "media_paste_failed",
                    "message": "Qianniu did not accept an approved media attachment; nothing was sent."])
            return
          }
          usleep(550_000)
          guard let current = scopedNodes(), activeCustomerMatches(expected, nodes: current) else {
            finish(["error": "media_customer_verification_failed",
                    "message": "The active customer changed while inserting media; nothing was sent."])
            return
          }
        }
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string), postCommandV() else {
          finish(["error": "reply_paste_failed",
                  "message": "The reply text could not be appended after media; nothing was sent."])
          return
        }
        usleep(350_000)
        let afterPaste = composerVisualFingerprint(pid: pid, frame: composer.frame)
        guard beforePaste != nil, afterPaste != nil, beforePaste != afterPaste else {
          finish(["error": "media_insert_unverified",
                  "message": "Qianniu did not visibly confirm the media insertion; nothing was sent."])
          return
        }
      }

      guard let verified = scopedNodes(), activeCustomerMatches(expected, nodes: verified),
            let verifiedComposer = verified.first(where: { $0.role == kAXTextAreaRole as String }),
            (requestedMedia.isEmpty
              ? stringAttribute(verifiedComposer.element, kAXValueAttribute) == text
              : true),
            let send = verified.first(where: {
              ($0.role == kAXButtonRole as String || $0.role == kAXMenuButtonRole as String) &&
                $0.title == "发送"
            }), let frame = send.frame else {
        _ = AXUIElementSetAttributeValue(composer.element, kAXValueAttribute as CFString, "" as CFTypeRef)
        finish(["error": "pre_send_verification_failed",
                "message": "Customer, inserted text, or Send control verification failed. The inserted text was cleared."])
        return
      }

      // A coordinate click is used only after bringing Qianniu frontmost and
      // re-verifying the exact customer and composer state.
      _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
      usleep(150_000)
      guard let finalNodes = scopedNodes(), activeCustomerMatches(expected, nodes: finalNodes) else {
        finish(["error": "final_customer_verification_failed",
                "message": "The expected customer was no longer active; nothing was sent."])
        return
      }
      let point = CGPoint(x: frame.midX, y: frame.midY)
      guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                             mouseCursorPosition: point, mouseButton: .left) else {
        finish(["error": "send_click_failed", "message": "Could not create the Send click event."])
        return
      }
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      usleep(450_000)

      guard let after = scopedNodes(), activeCustomerMatches(expected, nodes: after),
            let afterComposer = after.first(where: { $0.role == kAXTextAreaRole as String }),
            (stringAttribute(afterComposer.element, kAXValueAttribute) ?? "").isEmpty else {
        finish(["error": "send_unconfirmed",
                "message": "Send was clicked once, but Qianniu did not clear the composer. Do not retry automatically; verify in Qianniu."])
        return
      }
      finish(["sent": true, "customer": expected, "reply": text,
              "mediaCount": requestedMedia.count])
    }
  }

  /// Hashes the visible composer before and after paste. This does not inspect
  /// customer media content; it only proves that Qianniu visibly changed the
  /// verified composer before the single Send action is allowed.
  private func composerVisualFingerprint(pid: pid_t, frame: CGRect?) -> String? {
    guard let frame, CGPreflightScreenCaptureAccess(),
          let rows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
    for row in rows where (row[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid {
      guard let number = row[kCGWindowNumber as String] as? NSNumber,
            let dictionary = row[kCGWindowBounds as String] as? [String: Any],
            let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
            bounds.intersects(frame),
            let image = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                CGWindowID(number.uint32Value),
                                                [.boundsIgnoreFraming, .bestResolution]) else { continue }
      let scaleX = CGFloat(image.width) / max(bounds.width, 1)
      let scaleY = CGFloat(image.height) / max(bounds.height, 1)
      let local = CGRect(x: (frame.minX - bounds.minX) * scaleX,
                         y: (frame.minY - bounds.minY) * scaleY,
                         width: frame.width * scaleX,
                         height: frame.height * scaleY).integral
        .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
      guard local.width >= 20, local.height >= 20,
            let crop = image.cropping(to: local),
            let data = NSBitmapImageRep(cgImage: crop)
              .representation(using: .png, properties: [:]) else { continue }
      return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    return nil
  }

  private func activeCustomerMatches(_ expected: String, nodes: [AXNode]) -> Bool {
    guard let composer = nodes.first(where: { $0.role == kAXTextAreaRole as String }),
          let split = nodes
            .filter({ $0.role == kAXSplitGroupRole as String && composer.path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }),
          let frame = split.frame else { return false }
    // JD places other labels before the customer name in some header layouts.
    // Do not treat the leftmost text as the identity; require a positive match
    // inside the active chat's header region instead.
    let headerMatches = nodes.contains { node in
      guard node.role == kAXStaticTextRole as String,
            let text = node.text, let candidate = node.frame else { return false }
      return candidate.minX >= frame.minX && candidate.maxX <= frame.maxX &&
        candidate.maxY <= frame.minY && candidate.minY >= frame.minY - 100 &&
        visibleCustomerIdentityMatches(text, expected: expected)
    }
    if headerMatches { return true }

    let jdHeaderMatches = nodes.contains { node in
      guard node.role == kAXStaticTextRole as String,
            let text = node.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            let candidate = node.frame else { return false }
      return exactCustomerIdentityMatches(text, expected) &&
        candidate.minX >= frame.minX && candidate.maxX <= frame.maxX &&
        candidate.minY >= frame.minY && candidate.maxY <= frame.minY + 70
    }
    if jdHeaderMatches { return true }

    // JD sometimes exposes the complete active account only in its details
    // panel. The sidebar is to the left and cannot satisfy this region.
    return nodes.contains { node in
      guard node.role == kAXStaticTextRole as String,
            let text = node.text?.trimmingCharacters(in: .whitespacesAndNewlines),
            let candidate = node.frame else { return false }
      return candidate.minX >= frame.maxX && exactCustomerIdentityMatches(text, expected)
    }
  }

  func inspectTree(maxDepth: Int) -> [String: Any] {
    guard AXIsProcessTrusted() else { return ["error": "accessibility_not_trusted", "tree": "Grant Accessibility access, then retry."] }
    guard let pid = runningPID() else { return ["error": "jd_not_running", "tree": "JD 咚咚工作台 is not running."] }
    let app = AXUIElementCreateApplication(pid)
    var lines: [String] = ["bundle=\(bundleIdentifier) pid=\(pid)"]
    var count = 0
    walk(app, path: "app", depth: 0, maxDepth: min(maxDepth, 30), maxNodes: 4_000) { node, depth in
      count += 1
      lines.append(String(repeating: "  ", count: depth) + describe(node))
    }
    let output = lines.joined(separator: "\n")
    return ["pid": Int(pid), "nodeCount": count, "tree": output]
  }

  private func runningPID() -> pid_t? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .first(where: { !$0.isTerminated })?.processIdentifier
  }

  /// Returns the AX split that owns the active conversation and composer.
  /// Its horizontal bounds exclude both the customer sidebar and details
  /// panel, allowing OCR to reject text that belongs to another row.
  func activeChatFrame() -> CGRect? {
    guard AXIsProcessTrusted(), let pid = runningPID() else { return nil }
    let root = AXUIElementCreateApplication(pid)
    var nodes: [AXNode] = []
    walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) {
      node, _ in nodes.append(node)
    }
    guard let window = nodes.first(where: {
      $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
    }) else { return nil }
    let scoped = nodes.filter {
      $0.path == window.path || $0.path.hasPrefix(window.path + "/")
    }
    guard let composer = scoped.first(where: { $0.role == kAXTextAreaRole as String }) else {
      return nil
    }
    return scoped
      .filter({
        $0.role == kAXSplitGroupRole as String &&
          composer.path.hasPrefix($0.path + "/") && $0.frame != nil
      })
      .max(by: { $0.path.count < $1.path.count })?.frame
  }

  /// Resolves the exact active account from the clickable conversation group.
  /// Qianniu truncates the central header, but the corresponding group title
  /// contains the complete account name.
  func activeCustomerIdentity() -> String? {
    guard AXIsProcessTrusted(), let pid = runningPID() else { return nil }
    let root = AXUIElementCreateApplication(pid)
    var nodes: [AXNode] = []
    walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) { node, _ in nodes.append(node) }
    guard let window = nodes.first(where: {
      $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
    }) else { return nil }
    let scoped = nodes.filter {
      $0.path == window.path || $0.path.hasPrefix(window.path + "/")
    }
    if let composer = scoped.first(where: { $0.role == kAXTextAreaRole as String }),
       let split = scoped
        .filter({ $0.role == kAXSplitGroupRole as String && composer.path.hasPrefix($0.path + "/") })
        .max(by: { $0.path.count < $1.path.count }),
       let frame = split.frame {
      let exactHeaderIdentity = scoped.compactMap { node -> (String, CGRect)? in
         guard node.role == kAXStaticTextRole as String,
               let text = node.text?.trimmingCharacters(in: .whitespacesAndNewlines),
               let identity = cleanedRowCustomerIdentity(text),
               let candidate = node.frame,
               candidate.minX >= frame.minX && candidate.maxX <= frame.maxX,
               candidate.minY >= frame.minY && candidate.maxY <= frame.minY + 70
         else { return nil }
         return (identity, candidate)
       }.min { left, right in
         if abs(left.1.minX - right.1.minX) > 2 { return left.1.minX < right.1.minX }
         return left.1.minY < right.1.minY
       }?.0
      if let exactHeaderIdentity { return exactHeaderIdentity }
    }
    let conversations = scoped.filter {
      $0.role == kAXGroupRole as String && $0.actions.contains(kAXPressAction as String) &&
        !($0.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
    if conversations.count == 1 { return conversations[0].title }

    guard let composer = scoped.first(where: { $0.role == kAXTextAreaRole as String }),
          let split = scoped
            .filter({ $0.role == kAXSplitGroupRole as String && composer.path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }),
          let frame = split.frame,
          let header = scoped.first(where: { node in
            guard node.role == kAXStaticTextRole as String, let candidate = node.frame,
                  let text = node.text, !text.isEmpty else { return false }
            return candidate.minX >= frame.minX && candidate.maxX <= frame.maxX &&
              candidate.maxY <= frame.minY && candidate.minY >= frame.minY - 100
          })?.text else { return nil }
    let matches = conversations.compactMap(\.title).filter {
      visibleCustomerIdentityMatches(header, expected: $0)
    }
    if matches.count == 1 { return matches[0] }
    return cleanedRowCustomerIdentity(header)
  }

  func conversationIdentities() -> [String] {
    conversationRows().compactMap { $0["customer"] as? String }
  }

  /// Launches Qianniu when needed and opens its verified Accessibility button
  /// for the customer-service reception center. This never selects a customer,
  /// changes the composer, or sends a message.
  func ensureReceptionWindow(allowActivation: Bool = true,
                              completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      guard AXIsProcessTrusted() else {
        finish(["error": "accessibility_not_allowed",
                "message": "Accessibility permission is required to open Qianniu's reception center."])
        return
      }
      if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .first(where: { !$0.isTerminated }) {
        if !allowActivation {
          let root = AXUIElementCreateApplication(app.processIdentifier)
          var nodes: [AXNode] = []
          self.walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) {
            node, _ in nodes.append(node)
          }
          guard let reception = nodes.first(where: {
            $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
          }) else {
            finish(["error": "reception_window_missing",
                    "message": "Qianniu is running, but the reception window is not open. Passive monitoring will not activate it."])
            return
          }
          var minimizedValue: CFTypeRef?
          let minimized = AXUIElementCopyAttributeValue(
            reception.element, kAXMinimizedAttribute as CFString, &minimizedValue) == .success &&
            (minimizedValue as? NSNumber)?.boolValue == true
          guard !minimized, !app.isHidden else {
            finish(["error": "reception_window_hidden",
                    "message": "Qianniu's reception window is hidden or minimized. Passive monitoring will not restore it."])
            return
          }
          finish(["ready": true, "opened": false, "method": "passive_existing_window"])
          return
        }
        finish(self.openReceptionWindow(app: app))
        return
      }
      guard allowActivation else {
        finish(["error": "qianniu_not_running",
                "message": "Qianniu is not running. Passive monitoring will not launch it."])
        return
      }
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        finish(["error": "qianniu_not_installed",
                "message": "The installed Qianniu application could not be located."])
        return
      }
      DispatchQueue.main.async {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] app, error in
          guard let self else { return }
          self.queue.async {
            if let error {
              finish(["error": "qianniu_launch_failed", "message": error.localizedDescription])
              return
            }
            guard let app else {
              finish(["error": "qianniu_launch_failed", "message": "Qianniu did not launch."])
              return
            }
            for _ in 0..<20 {
              let response = self.openReceptionWindow(app: app)
              if response["ready"] as? Bool == true {
                finish(response)
                return
              }
              usleep(250_000)
            }
            finish(["error": "reception_window_missing",
                    "message": "Qianniu launched, but its reception center did not become available."])
          }
        }
      }
    }
  }

  private func openReceptionWindow(app: NSRunningApplication) -> [String: Any] {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    func snapshot() -> [AXNode] {
      var nodes: [AXNode] = []
      walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) {
        node, _ in nodes.append(node)
      }
      return nodes
    }
    var nodes = snapshot()
    if let reception = nodes.first(where: {
      $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
    }) {
      var minimizedValue: CFTypeRef?
      let minimized = AXUIElementCopyAttributeValue(
        reception.element, kAXMinimizedAttribute as CFString, &minimizedValue) == .success &&
        (minimizedValue as? NSNumber)?.boolValue == true
      if minimized {
        _ = app.unhide()
        _ = app.activate(options: [.activateIgnoringOtherApps])
        _ = AXUIElementSetAttributeValue(
          reception.element, kAXMinimizedAttribute as CFString, false as CFTypeRef)
        usleep(250_000)
        return ["ready": true, "opened": true, "method": "restored_minimized_window"]
      }
      return ["ready": true, "opened": false, "method": "already_open"]
    }
    // A minimized/hidden main workbench may omit all of its child buttons from
    // the AX snapshot. Restore it once, then resolve the exact named control.
    _ = app.unhide()
    _ = app.activate(options: [.activateIgnoringOtherApps])
    usleep(300_000)
    nodes = snapshot()
    guard let button = nodes.first(where: {
      $0.role == kAXButtonRole as String && $0.title == "接待中心" &&
        $0.actions.contains(kAXPressAction as String)
    }) else {
      return ["error": "reception_button_missing",
              "message": "Qianniu is running, but its verified 接待中心 button is unavailable."]
    }
    _ = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
    for _ in 0..<12 {
      usleep(125_000)
      nodes = snapshot()
      if nodes.contains(where: {
        $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
      }) {
        return ["ready": true, "opened": true, "method": "verified_ax_press"]
      }
    }
    return ["error": "reception_open_failed",
            "message": "Qianniu did not expose a reception window after the verified 接待中心 button was pressed."]
  }

  /// Returns exact AX identities plus screenshot-derived unread evidence.
  /// The red-pixel detector is only a priority hint; Flutter still performs a
  /// fallback scan of every visible row to avoid losing messages.
  func conversationRows() -> [[String: Any]] {
    guard AXIsProcessTrusted(), let pid = runningPID() else { return [] }
    let root = AXUIElementCreateApplication(pid)
    var nodes: [AXNode] = []
    walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) { node, _ in nodes.append(node) }
    guard let window = nodes.first(where: {
      $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
    }) else { return [] }
    guard let windowFrame = window.frame else { return [] }
    let activeFallback: () -> [[String: Any]] = { [weak self] in
      guard let customer = self?.activeCustomerIdentity(), !customer.isEmpty else {
        return []
      }
      return [[
        "customer": customer,
        "unread": false,
        "unreadEvidence": 0,
        "evidenceAvailable": false,
      ]]
    }
    // A one-customer JD layout can expose the active identity in the verified
    // chat header while omitting a usable screenshot/pressable sidebar row.
    // Keep monitoring that active conversation instead of reporting zero rows.
    guard let evidence = unreadScreenshot(pid: pid) else {
      return activeFallback()
    }
    let customerGroups = nodes.compactMap { node -> (String, CGRect)? in
      guard node.path.hasPrefix(window.path + "/"),
            node.role == kAXGroupRole as String,
            node.actions.contains(kAXPressAction as String),
            let frame = node.frame,
            frame.minX >= windowFrame.minX,
            frame.maxX <= windowFrame.minX + windowFrame.width * 0.35,
            frame.minY >= windowFrame.minY + 180,
            frame.maxY <= windowFrame.maxY - 30,
            frame.width >= 140, frame.width <= 360,
            frame.height >= 35, frame.height <= 100,
            let customer = customerIDInRow(
              frame: frame, windowBounds: evidence.bounds, image: evidence.image)
      else { return nil }
      return (customer, frame)
    }
    var seen = Set<String>()
    let unique = customerGroups.filter { seen.insert($0.0).inserted }
    if unique.isEmpty { return activeFallback() }
    return unique.map { customer, frame in
      let redPixels = unreadRedPixels(
        frame: frame, windowBounds: evidence.bounds, image: evidence.image)
      return [
        "customer": customer,
        "unread": redPixels >= 8,
        "unreadEvidence": redPixels,
        "evidenceAvailable": true,
      ]
    }
  }

  func openConversation(expectedCustomer: String, allowActivation: Bool = true,
                        completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !expected.isEmpty, AXIsProcessTrusted(), let pid = runningPID() else {
        finish(["error": "conversation_unavailable", "message": "Qianniu, Accessibility, or customer ID is unavailable."])
        return
      }
      let root = AXUIElementCreateApplication(pid)
      var nodes: [AXNode] = []
      walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) { node, _ in nodes.append(node) }
      guard let window = nodes.first(where: {
        $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
      }) else {
        finish(["error": "conversation_window_missing",
                "message": "Qianniu's reception window is not available."])
        return
      }
      let scoped = nodes.filter {
        $0.path == window.path || $0.path.hasPrefix(window.path + "/")
      }
      if activeCustomerMatches(expected, nodes: scoped) {
        finish(["opened": true, "customer": expected, "method": "already_active"])
        return
      }
      let evidence = unreadScreenshot(pid: pid)
      let candidates = scoped.filter { node in
        guard node.role == kAXGroupRole as String,
              node.actions.contains(kAXPressAction as String),
              let frame = node.frame,
              let evidence,
              let customer = customerIDInRow(
                frame: frame, windowBounds: evidence.bounds, image: evidence.image)
        else { return false }
        return exactCustomerIdentityMatches(customer, expected)
      }
      guard let target = candidates.min(by: {
        ($0.frame?.minX ?? .greatestFiniteMagnitude) <
          ($1.frame?.minX ?? .greatestFiniteMagnitude)
      }) else {
        finish(["error": "conversation_not_found", "message": "Exact conversation \(expected) was not found."])
        return
      }

      func verified() -> Bool {
        if activeCustomerIdentity().map({ exactCustomerIdentityMatches($0, expected) }) == true {
          return true
        }
        var current: [AXNode] = []
        walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) {
          node, _ in current.append(node)
        }
        return activeCustomerMatches(expected, nodes: current)
      }

      if verified() {
        finish(["opened": true, "customer": expected, "method": "already_active"])
        return
      }

      // Switching an embedded Qianniu chat ultimately requires keyboard/mouse
      // focus on builds that ignore AXPress. A background monitor must defer
      // instead of interrupting typing in VS Code or another application.
      guard allowActivation ||
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        finish(["error": "qianniu_not_frontmost",
                "message": "Unread conversation is queued until Qianniu is frontmost; focus was not stolen."])
        return
      }

      // Try the verified AX action in the background first. Qianniu may accept
      // it without stealing focus. Only the guarded coordinate fallback below
      // activates Qianniu when its embedded web view ignores AXPress.
      if let composer = scoped.first(where: { $0.role == kAXTextAreaRole as String }),
         !(stringAttribute(composer.element, kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
        finish(["error": "composer_not_empty",
                "message": "Automatic switching paused because the current composer contains text."])
        return
      }

      _ = AXUIElementPerformAction(target.element, kAXPressAction as CFString)
      for _ in 0..<8 {
        usleep(125_000)
        if verified() {
          finish(["opened": true, "customer": expected, "method": "ax_press"])
          return
        }
      }

      // Qianniu's embedded web view sometimes advertises AXPress but ignores it.
      // Fall back to one click on the already identity-matched sidebar row, then
      // verify the active customer again before OCR is allowed to continue.
      guard let frame = target.frame else {
        finish(["error": "conversation_verification_failed",
                "message": "Qianniu ignored AXPress for \(expected), and the verified sidebar row had no clickable frame."])
        return
      }
      // Reaching this point proves either activation was explicitly allowed or
      // Qianniu was already frontmost. Passive monitoring may click a verified
      // row only in the latter case; it still never steals focus.
      if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
        _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps])
        usleep(150_000)
      }
      let point = CGPoint(x: frame.midX, y: frame.midY)
      guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                               mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                             mouseCursorPosition: point, mouseButton: .left) else {
        finish(["error": "conversation_click_failed",
                "message": "Could not create a guarded click for \(expected)."])
        return
      }
      down.post(tap: .cghidEventTap)
      up.post(tap: .cghidEventTap)
      for _ in 0..<12 {
        usleep(125_000)
        if verified() {
          finish(["opened": true, "customer": expected, "method": "guarded_click"])
          return
        }
      }
      finish(["error": "conversation_verification_failed",
              "message": "Qianniu did not activate the expected customer \(expected) after AXPress and a guarded row click."])
    }
  }

  /// Scrolls only the verified active chat viewport. Positive values reveal
  /// older/upper content; negative values return toward the newest message.
  func scrollConversation(expectedCustomer: String, deltaY: Int32,
                          completion: @escaping FlutterResult) {
    queue.async { [weak self] in
      guard let self else { return }
      func finish(_ payload: [String: Any]) {
        DispatchQueue.main.async { completion(payload) }
      }
      let expected = expectedCustomer.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !expected.isEmpty, deltaY != 0, AXIsProcessTrusted(),
            let pid = runningPID() else {
        finish(["error": "scroll_precondition_failed",
                "message": "Customer, scroll amount, or Accessibility is unavailable."])
        return
      }
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        finish(["error": "qianniu_not_frontmost",
                "message": "Qianniu is not active. Chat scrolling was deferred without stealing focus."])
        return
      }
      let root = AXUIElementCreateApplication(pid)
      var nodes: [AXNode] = []
      walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) {
        node, _ in nodes.append(node)
      }
      guard activeCustomerMatches(expected, nodes: nodes),
            let composer = nodes.first(where: { $0.role == kAXTextAreaRole as String }),
            let composerFrame = composer.frame,
            (stringAttribute(composer.element, kAXValueAttribute)?
              .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
            let split = nodes
              .filter({ $0.role == kAXSplitGroupRole as String && composer.path.hasPrefix($0.path + "/") })
              .max(by: { $0.path.count < $1.path.count }),
            let splitFrame = split.frame else {
        finish(["error": "scroll_verification_failed",
                "message": "The exact active chat viewport or empty composer could not be verified."])
        return
      }
      let messageBottom = min(composerFrame.minY, splitFrame.maxY)
      let point = CGPoint(x: splitFrame.midX,
                          y: splitFrame.minY + (messageBottom - splitFrame.minY) * 0.55)
      guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                               mouseCursorPosition: point, mouseButton: .left),
            let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                 wheelCount: 1, wheel1: deltaY,
                                 wheel2: 0, wheel3: 0) else {
        finish(["error": "scroll_event_failed",
                "message": "Could not create a guarded chat scroll event."])
        return
      }
      move.post(tap: .cghidEventTap)
      scroll.post(tap: .cghidEventTap)
      usleep(450_000)
      var after: [AXNode] = []
      walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) {
        node, _ in after.append(node)
      }
      guard activeCustomerMatches(expected, nodes: after) else {
        finish(["error": "scroll_customer_changed",
                "message": "The active customer changed during scrolling."])
        return
      }
      finish(["scrolled": true, "customer": expected, "deltaY": Int(deltaY)])
    }
  }

  private func poll() {
    guard AXIsProcessTrusted(), let pid = runningPID() else { return }
    let root = AXUIElementCreateApplication(pid)
    var nodes: [AXNode] = []
    walk(root, path: "app", depth: 0, maxDepth: 22, maxNodes: 5_000) { node, _ in nodes.append(node) }

    // Validated against Qianniu macOS 9.95.01. Scope all matching to the reception
    // window so similarly named controls in the workbench window cannot be selected.
    guard let receptionWindow = nodes.first(where: {
      $0.role == kAXWindowRole as String && ($0.title?.contains("咚咚融合工作台") == true)
    }) else {
      onDiagnostic?(["event": "reception_window_missing",
                     "hint": "Open Qianniu's customer-service reception center."])
      return
    }
    let scopedNodes = nodes.filter {
      $0.path == receptionWindow.path || $0.path.hasPrefix(receptionWindow.path + "/")
    }
    guard let composer = scopedNodes.first(where: { $0.role == kAXTextAreaRole as String }),
          let splitGroup = scopedNodes
            .filter({ $0.role == kAXSplitGroupRole as String && composer.path.hasPrefix($0.path + "/") })
            .max(by: { $0.path.count < $1.path.count }) else {
      onDiagnostic?(["event": "composer_missing",
                     "hint": "Keep an active conversation open and inspect the AX tree again."])
      return
    }

    guard let splitFrame = splitGroup.frame,
          let customerNode = scopedNodes
            .filter({ node in
              guard node.role == "AXStaticText", let frame = node.frame,
                    let text = node.text, !text.isEmpty else { return false }
              return frame.minX >= splitFrame.minX && frame.maxX <= splitFrame.maxX &&
                frame.maxY <= splitFrame.minY && frame.minY >= splitFrame.minY - 100
            })
            .max(by: { ($0.frame?.minY ?? 0) < ($1.frame?.minY ?? 0) }),
          let customerName = customerNode.text else {
      onDiagnostic?(["event": "customer_identity_missing",
                     "splitFrame": normalizedFrame(splitGroup.frame)])
      return
    }
    let conversationKey = stableConversationKey(customerNode, customerName: customerName)
    lastActiveConversation = conversationKey

    // The live dump exposes message history as AXSplitGroup/AXGroup/AXList and the
    // composer as AXTextArea. Restricting the list to this split group excludes the
    // sidebar and the customer/product panels.
    guard let composerFrame = composer.frame,
          let messageArea = scopedNodes
            .filter({ node in
              guard node.role == "AXList", let frame = node.frame else { return false }
              return node.path.hasPrefix(splitGroup.path + "/") && frame.maxY <= composerFrame.minY
            })
            .max(by: { ($0.frame?.width ?? 0) < ($1.frame?.width ?? 0) }) else {
      onDiagnostic?(["event": "message_list_missing", "customer": customerName])
      return
    }
    let messageNodes = scopedNodes.filter {
      $0.path.hasPrefix(messageArea.path + "/") && $0.role == "AXStaticText" && $0.text != nil
    }
    let captures: [[String: Any]] = messageNodes.compactMap { node in
      guard let body = node.text, body != customerName, body.count <= 20_000 else { return nil }
      let fingerprint = sha256([conversationKey, node.identifier ?? "", body, normalizedFrame(node.frame), node.path].joined(separator: "\u{1f}"))
      guard seenFingerprints.insert(fingerprint).inserted else { return nil }
      return [
        "stableId": node.identifier.flatMap { $0.isEmpty ? nil : "ax:\($0)" } ?? "fp:\(fingerprint)",
        "direction": inferDirection(node: node, container: messageArea),
        "body": body,
        "axPath": node.path,
      ]
    }
    guard !captures.isEmpty else {
      onDiagnostic?(["event": "capture_ready", "customer": customerName,
                     "messageList": messageArea.path, "visibleMessages": messageNodes.count,
                     "note": "No unseen accessible messages are currently visible."])
      return
    }
    onCapture?([
      "stableKey": conversationKey,
      "customerName": customerName,
      "messages": captures,
      "capturedAtMs": Int(Date().timeIntervalSince1970 * 1000),
    ])
  }

  private func inferDirection(node: AXNode, container: AXNode) -> String {
    guard let x = node.frame?.midX, let middle = container.frame?.midX else { return "unknown" }
    return x < middle ? "incoming" : "outgoing"
  }

  private func stableConversationKey(_ identity: AXNode, customerName: String) -> String {
    if let identifier = identity.identifier, !identifier.isEmpty { return "ax:\(identifier)" }
    return "customer:\(sha256(customerName))"
  }

  private func descendantTexts(of ancestor: AXNode, in nodes: [AXNode]) -> [String] {
    nodes.lazy.filter { $0.path.hasPrefix(ancestor.path + "/") }
      .compactMap(\.text).filter { !$0.isEmpty }
  }

  private func walk(_ element: AXUIElement, path: String, depth: Int, maxDepth: Int,
                    maxNodes: Int, visit: (AXNode, Int) -> Void) {
    guard depth <= maxDepth else { return }
    var visited = 0
    func recurse(_ current: AXUIElement, _ currentPath: String, _ currentDepth: Int) {
      guard currentDepth <= maxDepth, visited < maxNodes else { return }
      visited += 1
      let node = makeNode(current, path: currentPath)
      visit(node, currentDepth)
      var roleCounts: [String: Int] = [:]
      for child in node.children {
        let role = stringAttribute(child, kAXRoleAttribute) ?? "AXUnknown"
        let index = roleCounts[role, default: 0]
        roleCounts[role] = index + 1
        recurse(child, "\(currentPath)/\(role)[\(index)]", currentDepth + 1)
      }
    }
    recurse(element, path, depth)
  }

  private func makeNode(_ element: AXUIElement, path: String) -> AXNode {
    var names: CFArray?
    AXUIElementCopyActionNames(element, &names)
    return AXNode(
      element: element,
      path: path,
      role: stringAttribute(element, kAXRoleAttribute) ?? "AXUnknown",
      subrole: stringAttribute(element, kAXSubroleAttribute),
      identifier: stringAttribute(element, kAXIdentifierAttribute),
      title: stringAttribute(element, kAXTitleAttribute),
      description: stringAttribute(element, kAXDescriptionAttribute),
      value: stringAttribute(element, kAXValueAttribute),
      help: stringAttribute(element, kAXHelpAttribute),
      frame: frameAttribute(element),
      actions: names as? [String] ?? [],
      children: elementArrayAttribute(element, kAXChildrenAttribute))
  }
}

private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
  if let string = value as? String { return string }
  if let number = value as? NSNumber { return number.stringValue }
  return nil
}

private func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
  return (value as? NSNumber)?.boolValue
}

private func elementArrayAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return [] }
  return value as? [AXUIElement] ?? []
}

private func frameAttribute(_ element: AXUIElement) -> CGRect? {
  var positionValue: CFTypeRef?
  var sizeValue: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
        let positionAX = positionValue, let sizeAX = sizeValue,
        CFGetTypeID(positionAX) == AXValueGetTypeID(), CFGetTypeID(sizeAX) == AXValueGetTypeID() else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  guard AXValueGetValue(positionAX as! AXValue, .cgPoint, &point),
        AXValueGetValue(sizeAX as! AXValue, .cgSize, &size) else { return nil }
  return CGRect(origin: point, size: size)
}

private func normalizedFrame(_ frame: CGRect?) -> String {
  guard let frame else { return "-" }
  return "\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))"
}

private func sha256(_ value: String) -> String {
  SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
}

private struct PasteboardSnapshot {
  private let items: [[NSPasteboard.PasteboardType: Data]]

  init(_ pasteboard: NSPasteboard) {
    items = (pasteboard.pasteboardItems ?? []).map { item in
      Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
        item.data(forType: type).map { (type, $0) }
      })
    }
  }

  func restore(to pasteboard: NSPasteboard) {
    pasteboard.clearContents()
    let restored = items.map { values -> NSPasteboardItem in
      let item = NSPasteboardItem()
      for (type, data) in values { item.setData(data, forType: type) }
      return item
    }
    if !restored.isEmpty { pasteboard.writeObjects(restored) }
  }
}

private func postCommandC() -> Bool {
  guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else { return false }
  down.flags = .maskCommand
  up.flags = .maskCommand
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  return true
}

private func postCommandV() -> Bool {
  guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else { return false }
  down.flags = .maskCommand
  up.flags = .maskCommand
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  return true
}

private func averageImageHash(_ image: CGImage) -> String {
  var pixels = [UInt8](repeating: 0, count: 64)
  let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
    guard let context = CGContext(data: buffer.baseAddress, width: 8, height: 8,
                                  bitsPerComponent: 8, bytesPerRow: 8,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
      return false
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
    return true
  }
  guard rendered else { return "" }
  let average = pixels.reduce(0) { $0 + Int($1) } / pixels.count
  var hash: UInt64 = 0
  for (index, pixel) in pixels.enumerated() where Int(pixel) >= average {
    hash |= UInt64(1) << UInt64(index)
  }
  return String(format: "%016llx", hash)
}

/// JD video thumbnails use a bright circular play ring near the media center.
/// OCR crops may include the sender avatar and surrounding whitespace, so scan
/// a small center area rather than assuming the ring is at the crop midpoint.
/// Requiring most angular sectors plus the center triangle avoids promoting
/// ordinary product photos merely because they contain one white control.
private func looksLikeVideoThumbnail(_ image: CGImage) -> Bool {
  let bitmap = NSBitmapImageRep(cgImage: image)
  let width = bitmap.pixelsWide
  let height = bitmap.pixelsHigh
  let shortest = Double(min(width, height))
  guard shortest >= 80 else { return false }
  let imageCenterX = Double(width - 1) / 2
  let imageCenterY = Double(height - 1) / 2

  func brightness(x: Int, y: Int) -> Double {
    guard x >= 0, y >= 0, x < width, y < height,
          let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
    else { return 0 }
    return 0.2126 * Double(color.redComponent) +
      0.7152 * Double(color.greenComponent) +
      0.0722 * Double(color.blueComponent)
  }

  func hasPlayControl(centerX: Double, centerY: Double,
                      nominalRadius: Double) -> Bool {
    var brightSectors = 0
    for sector in 0..<24 {
      let angle = Double(sector) * 2 * Double.pi / 24
      var maximum = 0.0
      for offset in -4...4 {
        let radius = nominalRadius + Double(offset)
        let x = Int((centerX + cos(angle) * radius).rounded())
        let y = Int((centerY + sin(angle) * radius).rounded())
        maximum = max(maximum, brightness(x: x, y: y))
      }
      if maximum >= 0.82 { brightSectors += 1 }
    }
    guard brightSectors >= 18 else { return false }

    var brightCenterSamples = 0
    for yOffset in stride(from: -0.035, through: 0.035, by: 0.0175) {
      for xOffset in stride(from: -0.015, through: 0.05, by: 0.01625) {
        let x = Int((centerX + shortest * xOffset).rounded())
        let y = Int((centerY + shortest * yOffset).rounded())
        if brightness(x: x, y: y) >= 0.82 { brightCenterSamples += 1 }
      }
    }
    return brightCenterSamples >= 5
  }

  for yOffset in stride(from: -0.12, through: 0.12, by: 0.02) {
    for xOffset in stride(from: -0.14, through: 0.14, by: 0.02) {
      let centerX = imageCenterX + Double(width) * xOffset
      let centerY = imageCenterY + Double(height) * yOffset
      for radiusRatio in stride(from: 0.065, through: 0.11, by: 0.01) {
        if hasPlayControl(centerX: centerX, centerY: centerY,
                          nominalRadius: shortest * radiusRatio) {
          return true
        }
      }
    }
  }
  return false
}

private func postClick(at point: CGPoint) -> Bool {
  guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left) else { return false }
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  usleep(100_000)
  return true
}

private func postHover(at point: CGPoint) -> Bool {
  guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                           mouseCursorPosition: point, mouseButton: .left)
  else { return false }
  move.post(tap: .cghidEventTap)
  usleep(250_000)
  return true
}

private func postCommandShiftG() -> Bool {
  guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 5, keyDown: false)
  else { return false }
  down.flags = [.maskCommand, .maskShift]
  up.flags = [.maskCommand, .maskShift]
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  return true
}

private func postDoubleClick(at point: CGPoint) -> Bool {
  guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                           mouseCursorPosition: point, mouseButton: .left),
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                         mouseCursorPosition: point, mouseButton: .left) else { return false }
  down.setIntegerValueField(.mouseEventClickState, value: 1)
  up.setIntegerValueField(.mouseEventClickState, value: 1)
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  usleep(80_000)
  down.setIntegerValueField(.mouseEventClickState, value: 2)
  up.setIntegerValueField(.mouseEventClickState, value: 2)
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  return true
}

private func postEscape() -> Bool {
  guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)
  else { return false }
  down.post(tap: .cghidEventTap)
  up.post(tap: .cghidEventTap)
  return true
}

private func closeJDImageViewer(pid: pid_t, bounds: CGRect) -> Bool {
  let app = AXUIElementCreateApplication(pid)
  for window in elementArrayAttribute(app, kAXWindowsAttribute) {
    let title = stringAttribute(window, kAXTitleAttribute) ?? ""
    guard title.contains("图片浏览器") else { continue }
    var closeValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(
      window, kAXCloseButtonAttribute as CFString, &closeValue) == .success,
       let closeValue,
       CFGetTypeID(closeValue) == AXUIElementGetTypeID() {
      _ = AXUIElementPerformAction(
        unsafeBitCast(closeValue, to: AXUIElement.self),
        kAXPressAction as CFString)
      usleep(100_000)
    }
  }
  if namedWindowBounds(pid: pid, containing: "图片浏览器") == nil { return true }

  // JD builds that do not expose AXCloseButton still use the standard macOS
  // close control at the top-left of this already verified viewer window.
  _ = postClick(at: CGPoint(x: bounds.minX + 20, y: bounds.minY + 20))
  usleep(100_000)
  if namedWindowBounds(pid: pid, containing: "图片浏览器") == nil { return true }

  _ = postEscape()
  usleep(100_000)
  return namedWindowBounds(pid: pid, containing: "图片浏览器") == nil
}

private func describe(_ node: AXNode) -> String {
  var fields = [node.role]
  if let subrole = node.subrole { fields.append("subrole=\(quoted(subrole))") }
  if let id = node.identifier { fields.append("id=\(quoted(id))") }
  if let title = node.title { fields.append("title=\(quoted(title))") }
  if let value = node.value { fields.append("value=\(quoted(value))") }
  if let description = node.description { fields.append("description=\(quoted(description))") }
  if let help = node.help { fields.append("help=\(quoted(help))") }
  if let frame = node.frame { fields.append("frame=\(normalizedFrame(frame))") }
  if !node.actions.isEmpty { fields.append("actions=\(node.actions)") }
  fields.append("path=\(node.path)")
  return fields.joined(separator: " ")
}

private func quoted(_ value: String) -> String {
  let clipped = value.count > 240 ? String(value.prefix(240)) + "…" : value
  return "\"\(clipped.replacingOccurrences(of: "\n", with: "\\n"))\""
}
