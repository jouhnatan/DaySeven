/// Where the application itself is installed.
///
/// On macOS the app is meant to live in the Applications folder. Running from
/// elsewhere — most often straight out of the Downloads folder after unzipping
/// — leaves the user with an unmanaged copy, so the app says so once and then
/// continues. It also blocks self-updating, which would otherwise replace a
/// bundle the person did not think of as installed. On Windows the app is
/// wherever its zip was extracted and no location is more correct than
/// another, so there is nothing to check.
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
