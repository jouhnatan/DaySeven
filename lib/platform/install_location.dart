/// Where the application itself is installed.
///
/// On macOS the app is meant to live in the Applications folder. Running from
/// elsewhere — most often straight out of the Downloads folder after unzipping
/// — leaves the user with an unmanaged copy, so the app says so once and then
/// continues. Windows installs through MSIX, which places the app itself, so
/// there is nothing to check there.
library;

import 'dart:io';

class InstallLocation {
  const InstallLocation({required this.isCorrect, required this.path});

  final bool isCorrect;
  final String path;
}

InstallLocation checkInstallLocation() {
  if (!Platform.isMacOS) {
    return InstallLocation(isCorrect: true, path: Platform.resolvedExecutable);
  }

  final executable = Platform.resolvedExecutable;
  // A debug or profile build runs from the build output, where this check is
  // only noise.
  const isRelease = bool.fromEnvironment('dart.vm.product');
  if (!isRelease) {
    return InstallLocation(isCorrect: true, path: executable);
  }

  final correct =
      executable.startsWith('/Applications/') ||
      executable.contains('${Platform.environment['HOME']}/Applications/');

  return InstallLocation(isCorrect: correct, path: executable);
}
