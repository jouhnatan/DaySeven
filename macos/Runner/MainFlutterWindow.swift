import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  static let defaultTrafficLightsOffsetX: CGFloat = 20.0
  static let defaultTrafficLightsOffsetY: CGFloat = 18.0

  private var trafficLightsOffsetX: CGFloat = defaultTrafficLightsOffsetX
  private var trafficLightsOffsetY: CGFloat = defaultTrafficLightsOffsetY
  private var windowChromeChannel: FlutterMethodChannel?
  private var newInstanceChannel: FlutterMethodChannel?
  private var macosLightsChannel: FlutterMethodChannel?

  func applyTrafficLightsPosition() {
    guard !styleMask.contains(.fullScreen) else { return }
    guard
      let closeButton = standardWindowButton(.closeButton),
      let miniButton = standardWindowButton(.miniaturizeButton),
      let zoomButton = standardWindowButton(.zoomButton)
    else {
      return
    }

    let superview = closeButton.superview
    let isFlipped = superview?.isFlipped ?? false
    let superviewHeight = superview?.bounds.height ?? self.frame.height
    let buttonHeight = closeButton.frame.height
    let y = isFlipped ? trafficLightsOffsetY : (superviewHeight - buttonHeight - trafficLightsOffsetY)

    let closeX = trafficLightsOffsetX
    let spacing: CGFloat = 6.0
    let miniX = closeX + closeButton.frame.width + spacing
    let zoomX = miniX + miniButton.frame.width + spacing

    closeButton.setFrameOrigin(NSPoint(x: closeX, y: y))
    miniButton.setFrameOrigin(NSPoint(x: miniX, y: y))
    zoomButton.setFrameOrigin(NSPoint(x: zoomX, y: y))
  }

  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    applyTrafficLightsPosition()
  }

  @objc private func onWindowDidResize(_ notification: Notification) {
    applyTrafficLightsPosition()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    titlebarAppearsTransparent = true

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(onWindowDidResize),
      name: NSWindow.didResizeNotification,
      object: self
    )

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

    let macosLights = FlutterMethodChannel(
      name: "dayseven/macos_lights",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    macosLights.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "setOffset":
        guard
          let arguments = call.arguments as? [String: Any],
          let x = arguments["x"] as? NSNumber,
          let y = arguments["y"] as? NSNumber
        else {
          result(FlutterError(
            code: "invalid_arguments",
            message: "setOffset requires numeric x and y values",
            details: nil
          ))
          return
        }
        self.trafficLightsOffsetX = CGFloat(truncating: x)
        self.trafficLightsOffsetY = CGFloat(truncating: y)
        self.applyTrafficLightsPosition()
        result(nil)
      case "resetOffset":
        self.trafficLightsOffsetX = Self.defaultTrafficLightsOffsetX
        self.trafficLightsOffsetY = Self.defaultTrafficLightsOffsetY
        self.applyTrafficLightsPosition()
        result(nil)
      case "getOffset":
        result([
          "x": Double(self.trafficLightsOffsetX),
          "y": Double(self.trafficLightsOffsetY),
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    macosLightsChannel = macosLights

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    applyTrafficLightsPosition()
  }
}
