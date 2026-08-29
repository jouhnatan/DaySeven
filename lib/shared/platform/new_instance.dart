/// Opening another copy of DaySeven.
///
/// The Dock icon's menu is the primary way to reach this; the in-app menu
/// calls the same native code so there is one implementation rather than two.
///
/// A *different account* copy takes a profile directory of its own and so
/// starts signed out, which is what makes it possible to watch a Knowledge
/// Base replicate between two accounts on one machine.
library;

import 'dart:io';

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('dayseven/new_instance');

/// macOS only. The Windows runner is single-window and has no equivalent.
bool get canOpenNewWindow => Platform.isMacOS;

class NewInstanceException implements Exception {
  const NewInstanceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Opens another copy.
///
/// [fresh] gives the new copy its own profile, and therefore its own login.
Future<void> openNewWindow({required bool fresh}) async {
  if (!canOpenNewWindow) return;
  try {
    await _channel.invokeMethod<void>('open', {'fresh': fresh});
  } on MissingPluginException {
    // No native side — tests, and any embedder that does not register it.
  } on PlatformException catch (error) {
    throw NewInstanceException(
      'Another DaySeven window could not be opened.'
      '${error.message == null ? '' : '\n\n${error.message}'}',
    );
  }
}
