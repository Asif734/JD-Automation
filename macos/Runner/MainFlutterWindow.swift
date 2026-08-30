import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var accessibilityBridge: AccessibilityBridge?

  override func awakeFromNib() {
    let controller = FlutterViewController()
    let windowFrame = frame
    contentViewController = controller
    setFrame(windowFrame, display: true)
    RegisterGeneratedPlugins(registry: controller)
    accessibilityBridge = AccessibilityBridge(messenger: controller.engine.binaryMessenger)
    super.awakeFromNib()
  }
}
