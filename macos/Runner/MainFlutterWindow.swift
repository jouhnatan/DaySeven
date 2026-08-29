import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var windowChromeChannel: FlutterMethodChannel?
  private var newInstanceChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    titlebarAppearsTransparent = true

    let channel = FlutterMethodChannel(
      name: "dayseven/window_chrome",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setBackgroundColor" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let number = arguments["argb"] as? NSNumber
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "setBackgroundColor requires an integer argb value",
          details: nil
        ))
        return
      }

      let argb = UInt32(truncating: number)
      let alpha = CGFloat((argb >> 24) & 0xff) / 255.0
      let red = CGFloat((argb >> 16) & 0xff) / 255.0
      let green = CGFloat((argb >> 8) & 0xff) / 255.0
      let blue = CGFloat(argb & 0xff) / 255.0
      self?.backgroundColor = NSColor(
        srgbRed: red,
        green: green,
        blue: blue,
        alpha: alpha
      )
      result(nil)
    }
    windowChromeChannel = channel

    let newInstance = FlutterMethodChannel(
      name: "dayseven/new_instance",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    newInstance.setMethodCallHandler { call, result in
      guard call.method == "open" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let fresh = arguments?["fresh"] as? Bool ?? false
      NewInstance.open(fresh: fresh) { error in
        if let error = error {
          result(FlutterError(
            code: "launch_failed",
            message: error.localizedDescription,
            details: nil
          ))
        } else {
          result(nil)
        }
      }
    }
    newInstanceChannel = newInstance

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
