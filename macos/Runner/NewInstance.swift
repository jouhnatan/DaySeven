import Cocoa

/// Launching another copy of DaySeven.
///
/// Two copies exist so that two accounts can be signed in at once, which is
/// the only way to watch a Knowledge Base replicate without two machines. The
/// copy is told which identity to take through its environment, because
/// `open` hands off to LaunchServices and LaunchServices does not carry the
/// caller's environment across. `NSWorkspace.OpenConfiguration` does.
enum NewInstance {
  /// Matches `kProfileModeVariable` in lib/shared/platform/app_profile.dart.
  static let profileVariable = "DAYSEVEN_PROFILE"

  /// Opens another copy.
  ///
  /// When `fresh` the copy takes a profile directory of its own and therefore
  /// starts signed out, ready for a second account. Otherwise it shares this
  /// one's directory and stays signed in as the same person.
  static func open(fresh: Bool, completion: ((Error?) -> Void)? = nil) {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.environment = [profileVariable: fresh ? "new" : "shared"]

    NSWorkspace.shared.openApplication(
      at: Bundle.main.bundleURL,
      configuration: configuration
    ) { _, error in
      DispatchQueue.main.async { completion?(error) }
    }
  }
}
