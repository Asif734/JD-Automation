import Foundation
import CoreGraphics
import AppKit

func usage() -> Never {
    fputs("usage: copy_region_text x y width height\n", stderr)
    exit(2)
}

guard CommandLine.arguments.count == 5,
      let x = Double(CommandLine.arguments[1]),
      let y = Double(CommandLine.arguments[2]),
      let width = Double(CommandLine.arguments[3]),
      let height = Double(CommandLine.arguments[4]) else {
    usage()
}

let pasteboard = NSPasteboard.general
pasteboard.clearContents()

let source = CGEventSource(stateID: .hidSystemState)
let start = CGPoint(x: x + 8, y: y + 8)
let end = CGPoint(x: x + width - 8, y: y + height - 8)

func postMouse(_ type: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
        return
    }
    event.post(tap: .cghidEventTap)
}

func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
    guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
        return
    }
    down.flags = flags
    up.flags = flags
    down.post(tap: .cghidEventTap)
    usleep(30_000)
    up.post(tap: .cghidEventTap)
}

postMouse(.leftMouseDown, start)
usleep(100_000)

let steps = 24
for step in 1...steps {
    let t = Double(step) / Double(steps)
    let point = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    postMouse(.leftMouseDragged, point)
    usleep(15_000)
}
postMouse(.leftMouseUp, end)
usleep(150_000)

postKey(8, flags: .maskCommand) // C
usleep(250_000)

if let text = pasteboard.string(forType: .string) {
    print(text)
}
