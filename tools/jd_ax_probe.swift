import ApplicationServices
import AppKit
import Foundation

let targetBundleIDs = ["com.jd.jdmddwb", "com.jd.jingmaiMac"]
let maxDepth = 14
let maxNodes = 4000

func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
  return value as? String
}

func children(_ element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else {
    return []
  }
  return value as? [AXUIElement] ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
  var positionValue: CFTypeRef?
  var sizeValue: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
        let positionAx = positionValue, let sizeAx = sizeValue,
        CFGetTypeID(positionAx) == AXValueGetTypeID(),
        CFGetTypeID(sizeAx) == AXValueGetTypeID() else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  guard AXValueGetValue(positionAx as! AXValue, .cgPoint, &point),
        AXValueGetValue(sizeAx as! AXValue, .cgSize, &size) else { return nil }
  return CGRect(origin: point, size: size)
}

let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
guard AXIsProcessTrustedWithOptions(promptOptions) else {
  fputs("ERROR: accessibility_not_allowed\n", stderr)
  exit(2)
}

for bundleID in targetBundleIDs {
  let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
  for app in apps where !app.isTerminated {
    print("APP bundle=\(bundleID) pid=\(app.processIdentifier) name=\(app.localizedName ?? "")")
    let root = AXUIElementCreateApplication(app.processIdentifier)
    var count = 0
    func walk(_ element: AXUIElement, path: String, depth: Int) {
      guard depth <= maxDepth, count < maxNodes else { return }
      count += 1
      let role = stringValue(element, kAXRoleAttribute as CFString) ?? "?"
      let title = stringValue(element, kAXTitleAttribute as CFString) ?? ""
      let value = stringValue(element, kAXValueAttribute as CFString) ?? ""
      let description = stringValue(element, kAXDescriptionAttribute as CFString) ?? ""
      let help = stringValue(element, kAXHelpAttribute as CFString) ?? ""
      let identifier = stringValue(element, kAXIdentifierAttribute as CFString) ?? ""
      let rect = frame(element).map { String(format: "%.0f,%.0f %.0fx%.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "-"
      let fields = [title, value, description, help, identifier]
        .map { $0.replacingOccurrences(of: "\n", with: "\\n") }
      print("\(path) role=\(role) frame=\(rect) title=\(fields[0].debugDescription) value=\(fields[1].debugDescription) desc=\(fields[2].debugDescription) help=\(fields[3].debugDescription) id=\(fields[4].debugDescription)")
      for (index, child) in children(element).enumerated() {
        walk(child, path: "\(path)/\(index)", depth: depth + 1)
      }
    }
    walk(root, path: "app", depth: 0)
    print("END nodes=\(count)")
  }
}
