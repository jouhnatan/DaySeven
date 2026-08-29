import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// The Dock icon's menu.
  ///
  /// This is the surface that works when the app has no window focused, and it
  /// is where a second window is most naturally reached from.
  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()

    let sameAccount = NSMenuItem(
      title: "New Window",
      action: #selector(openWindowSameAccount(_:)),
      keyEquivalent: ""
    )
    sameAccount.target = self
    menu.addItem(sameAccount)

    let otherAccount = NSMenuItem(
      title: "New Window as Different Account…",
      action: #selector(openWindowDifferentAccount(_:)),
      keyEquivalent: ""
    )
    otherAccount.target = self
    menu.addItem(otherAccount)

    return menu
  }

  @objc private func openWindowSameAccount(_ sender: Any?) {
    NewInstance.open(fresh: false)
  }

  @objc private func openWindowDifferentAccount(_ sender: Any?) {
    NewInstance.open(fresh: true)
  }
}
