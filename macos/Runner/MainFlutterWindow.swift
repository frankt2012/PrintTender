import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // Draw our own toolbar directly under the traffic lights instead of
    // stacking a second bar below a conventional title bar: keep the buttons,
    // hide the window title, and let Flutter fill the full window height.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true

    // The storyboard's 800x600 is the Flutter template default, and it is far
    // too tight once a sidebar, a print-hours panel and a schedule share the
    // window. Open at a size that fits the content, refuse to go below a size
    // that still shows a usable list, and remember whatever the user picks.
    let autosaveName = "PrintTenderMainWindow"
    if !self.setFrameUsingName(autosaveName) {
      var frame = self.frame
      frame.size = NSSize(width: 1180, height: 820)
      self.setFrame(frame, display: true)
      self.center()
    }
    self.minSize = NSSize(width: 900, height: 620)
    self.setFrameAutosaveName(autosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
