import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String,
       let item = NSApp.mainMenu?.items.first {
      item.title = name
      for entry in item.submenu?.items ?? [] {
        entry.title = entry.title.replacingOccurrences(of: "JD Automation", with: name)
      }
    }
  }
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
