import AppKit
import ApplicationServices
import Foundation

func axString(_ element: AXUIElement, _ attribute: String) -> String {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    if error != .success {
        return ""
    }
    if let string = value as? String {
        return string
    }
    if let attributed = value {
        return "\(attributed)"
    }
    return ""
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
       let children = value as? [AXUIElement] {
        return children
    }
    return []
}

func walk(_ element: AXUIElement, _ visit: (AXUIElement) -> Bool) -> AXUIElement? {
    if visit(element) {
        return element
    }
    for child in axChildren(element) {
        if let found = walk(child, visit) {
            return found
        }
    }
    return nil
}

func windowForReception(_ appElement: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
          let windows = value as? [AXUIElement] else {
        return nil
    }
    return windows.first { axString($0, kAXTitleAttribute).contains("接待中心") }
}

func textEntry(in window: AXUIElement) -> AXUIElement? {
    return walk(window) { element in
        let role = axString(element, kAXRoleAttribute)
        return role == kAXTextAreaRole || role == "AXTextEntryArea"
    }
}

func sendControl(in window: AXUIElement) -> AXUIElement? {
    return walk(window) { element in
        let role = axString(element, kAXRoleAttribute)
        let title = axString(element, kAXTitleAttribute)
        let description = axString(element, kAXDescriptionAttribute)
        return role == kAXMenuButtonRole && (title == "发送" || description == "发送")
    }
}

func pointAndSize(_ element: AXUIElement) -> (CGPoint, CGSize)? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionAX = positionValue,
          let sizeAX = sizeValue else {
        return nil
    }
    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionAX as! AXValue, .cgPoint, &point)
    AXValueGetValue(sizeAX as! AXValue, .cgSize, &size)
    return (point, size)
}

func mouseClick(center: CGPoint) {
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) else {
        return
    }
    down.post(tap: .cghidEventTap)
    usleep(80_000)
    up.post(tap: .cghidEventTap)
}

func mouseScroll(at point: CGPoint, amount: Int32) {
    let source = CGEventSource(stateID: .hidSystemState)
    if let move = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) {
        move.post(tap: .cghidEventTap)
        usleep(30_000)
    }
    guard let event = CGEvent(
        scrollWheelEvent2Source: source,
        units: .pixel,
        wheelCount: 1,
        wheel1: amount,
        wheel2: 0,
        wheel3: 0
    ) else {
        return
    }
    event.location = point
    event.post(tap: .cghidEventTap)
}

func collectElements(_ element: AXUIElement, into rows: inout [AXUIElement]) {
    rows.append(element)
    for child in axChildren(element) {
        collectElements(child, into: &rows)
    }
}

func visibleBuyerRows(in window: AXUIElement) -> [(title: String, point: CGPoint, size: CGSize)] {
    guard let (windowPoint, windowSize) = pointAndSize(window) else {
        return []
    }
    var elements: [AXUIElement] = []
    collectElements(window, into: &elements)
    let minX = windowPoint.x + 45
    let maxX = windowPoint.x + min(330, windowSize.width * 0.35)
    // The buyer list starts just below the "正在接待/全部买家/其他消息/联系人"
    // tabs. Keep this threshold high enough to skip the top navigation and low
    // enough to include the first visible buyer rows after scrolling.
    let minY = windowPoint.y + 225
    let maxY = windowPoint.y + windowSize.height - 25
    let rows = elements.compactMap { element -> (String, CGPoint, CGSize)? in
        let role = axString(element, kAXRoleAttribute)
        let title = axString(element, kAXTitleAttribute)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard role == kAXGroupRole,
              !title.isEmpty,
              !title.contains("全部买家"),
              !title.contains("咨询未"),
              !title.contains("最近星标"),
              !title.contains("正在接待"),
              let (point, size) = pointAndSize(element),
              point.x >= minX,
              point.x <= maxX,
              point.y >= minY,
              point.y <= maxY,
              size.height >= 18,
              size.height <= 85
        else {
            return nil
        }
        return (title, point, size)
    }
    var seen = Set<String>()
    return rows
        .sorted { lhs, rhs in
            if abs(lhs.1.y - rhs.1.y) > 2 { return lhs.1.y < rhs.1.y }
            return lhs.1.x < rhs.1.x
        }
        .filter { row in
            let key = "\(row.0)|\(Int(row.1.y))"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
}

func currentInputValue(_ input: AXUIElement) -> String {
    return axString(input, kAXValueAttribute)
}

func runProcess(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return 127
    }
}

func savePNG(_ image: CGImage, to path: String) -> Bool {
    let bitmap = NSBitmapImageRep(cgImage: image)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        return false
    }
    do {
        try data.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        return false
    }
}

func findQianNiuApp() -> NSRunningApplication? {
    return NSWorkspace.shared.runningApplications.first { app in
        if app.bundleIdentifier == "com.taobao.Aliworkbench" {
            return true
        }
        if app.localizedName == "Aliworkbench" || app.localizedName == "千牛" {
            return true
        }
        if app.executableURL?.lastPathComponent == "Aliworkbench" {
            return true
        }
        if app.bundleURL?.lastPathComponent == "Aliworkbench.app" {
            return true
        }
        return false
    }
}

func pgrepPID(named processName: String) -> pid_t? {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    process.arguments = ["-x", processName]
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
    } catch {
        return nil
    }
    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8) else {
        return nil
    }
    return output
        .split(whereSeparator: \.isNewline)
        .compactMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        .first
}

func main() -> Int32 {
    var args = Array(CommandLine.arguments.dropFirst())
    var explicitPID: pid_t?
    if args.count >= 2, args[0] == "--pid" {
        explicitPID = pid_t(args[1])
        args.removeFirst(2)
    }
    guard !args.isEmpty else {
        fputs("usage: qianniu_ax [--pid pid] status|dump-buyers|click-buyer <title>|scroll-buyers [amount]|fill|send|fill-send [text]\n", stderr)
        return 2
    }
    guard let pid = explicitPID ?? findQianNiuApp()?.processIdentifier ?? pgrepPID(named: "Aliworkbench") else {
        fputs("Aliworkbench is not running\n", stderr)
        return 3
    }

    let appElement = AXUIElementCreateApplication(pid)
    guard let window = windowForReception(appElement) else {
        fputs("QianNiu reception window not found\n", stderr)
        return 4
    }
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    let command = args[0]
    if command == "status" {
        print("ok")
        return 0
    }
    if command == "window-frame" {
        if let (point, size) = pointAndSize(window) {
            print("\(Int(point.x))\t\(Int(point.y))\t\(Int(size.width))\t\(Int(size.height))")
            return 0
        }
        return 10
    }
    if command == "dump-left" {
        guard let (windowPoint, windowSize) = pointAndSize(window) else {
            return 10
        }
        var elements: [AXUIElement] = []
        collectElements(window, into: &elements)
        let rows = elements.compactMap { element -> (CGPoint, CGSize, String, String, String, String)? in
            guard let (point, size) = pointAndSize(element),
                  point.x >= windowPoint.x,
                  point.x <= windowPoint.x + min(380, windowSize.width),
                  point.y >= windowPoint.y,
                  point.y <= windowPoint.y + windowSize.height
            else {
                return nil
            }
            let role = axString(element, kAXRoleAttribute)
            let title = axString(element, kAXTitleAttribute).replacingOccurrences(of: "\n", with: " ")
            let desc = axString(element, kAXDescriptionAttribute).replacingOccurrences(of: "\n", with: " ")
            let value = axString(element, kAXValueAttribute).replacingOccurrences(of: "\n", with: " ")
            guard !title.isEmpty || !desc.isEmpty || !value.isEmpty else {
                return nil
            }
            return (point, size, role, title, desc, value)
        }
        for row in rows.sorted(by: {
            if abs($0.0.y - $1.0.y) > 2 { return $0.0.y < $1.0.y }
            return $0.0.x < $1.0.x
        }) {
            print("\(Int(row.0.x))\t\(Int(row.0.y))\t\(Int(row.1.width))\t\(Int(row.1.height))\t\(row.2)\tT=\(row.3)\tD=\(row.4)\tV=\(row.5)")
        }
        return 0
    }
    if command == "dump-buyers" {
        for (index, row) in visibleBuyerRows(in: window).enumerated() {
            print("\(index + 1)\t\(Int(row.point.x))\t\(Int(row.point.y))\t\(Int(row.size.width))\t\(Int(row.size.height))\t\(row.title)")
        }
        return 0
    }
    if command == "click-buyer" {
        let wanted = args.dropFirst(1).joined(separator: " ")
        guard !wanted.isEmpty else {
            fputs("missing buyer title\n", stderr)
            return 2
        }
        guard let row = visibleBuyerRows(in: window).first(where: { $0.title == wanted || $0.title.contains(wanted) }) else {
            fputs("buyer not visible: \(wanted)\n", stderr)
            return 9
        }
        mouseClick(center: CGPoint(x: row.point.x + row.size.width / 2, y: row.point.y + row.size.height / 2))
        print("clicked\t\(row.title)")
        return 0
    }
    if command == "scroll-buyers" {
        let amount = args.count >= 2 ? Int32(args[1]) ?? -620 : -620
        guard let (windowPoint, _) = pointAndSize(window) else {
            fputs("window frame unavailable\n", stderr)
            return 10
        }
        mouseScroll(at: CGPoint(x: windowPoint.x + 185, y: windowPoint.y + 500), amount: amount)
        usleep(300_000)
        print("scrolled\t\(amount)")
        return 0
    }
    if command == "capture-chat" {
        let path = args.count >= 2 ? args[1] : "/private/tmp/qianniu_chat_capture.png"
        let code = runProcess("/usr/sbin/screencapture", ["-x", "-D", "2", "-R", "320,100,420,470", path])
        if code == 0 {
            print(path)
        }
        return code
    }
    if command == "display-bounds" {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        for (index, display) in displays.enumerated() {
            let bounds = CGDisplayBounds(display)
            print("\(index + 1)\t\(display)\t\(Int(bounds.origin.x))\t\(Int(bounds.origin.y))\t\(Int(bounds.width))\t\(Int(bounds.height))")
        }
        return 0
    }
    if command == "capture-display-cg" {
        let displayIndex = args.count >= 2 ? Int(args[1]) ?? 1 : 1
        let path = args.count >= 3 ? args[2] : "/private/tmp/qianniu_display_capture.png"
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        guard displayIndex >= 1, displayIndex <= displays.count,
              let image = CGDisplayCreateImage(displays[displayIndex - 1]) else {
            fputs("display capture failed\n", stderr)
            return 11
        }
        if savePNG(image, to: path) {
            print(path)
            return 0
        }
        return 12
    }
    guard let input = textEntry(in: window) else {
        fputs("QianNiu input not found\n", stderr)
        return 5
    }

    if command == "fill" || command == "fill-send" {
        let text = args.dropFirst(1).joined(separator: " ")
        let error = AXUIElementSetAttributeValue(input, kAXValueAttribute as CFString, text as CFString)
        if error != .success {
            fputs("failed to set input: \(error.rawValue)\n", stderr)
            return 6
        }
        print("filled")
        if command == "fill" {
            return 0
        }
        usleep(150_000)
    }

    guard let send = sendControl(in: window) else {
        fputs("QianNiu send control not found\n", stderr)
        return 7
    }
    AXUIElementPerformAction(send, kAXPressAction as CFString)
    usleep(250_000)
    if !currentInputValue(input).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let (point, size) = pointAndSize(send) {
        mouseClick(center: CGPoint(x: point.x + size.width / 2, y: point.y + size.height / 2))
        usleep(250_000)
    }
    if currentInputValue(input).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        print("sent")
        return 0
    }
    print("filled_not_sent")
    return 8
}

exit(main())
