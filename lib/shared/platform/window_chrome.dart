/// Synchronizes Flutter's application background with native desktop chrome.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('dayseven/window_chrome');

/// Keeps the native title bar visually continuous with the Flutter background.
///
/// [MaterialApp] rebuilds its builder when the system brightness changes, so a
/// wrapper placed there receives the active theme color for both startup and
/// live light/dark-mode changes.
class WindowChromeSync extends StatefulWidget {
  const WindowChromeSync({
    required this.backgroundColor,
    required this.child,
    super.key,
  });

  final Color backgroundColor;
  final Widget child;

  @override
  State<WindowChromeSync> createState() => _WindowChromeSyncState();
}

class _WindowChromeSyncState extends State<WindowChromeSync> {
  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(WindowChromeSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundColor != widget.backgroundColor) _sync();
  }

  void _sync() {
    if (defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }

    unawaited(_setNativeBackground(widget.backgroundColor));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _setNativeBackground(Color color) async {
  try {
    await _channel.invokeMethod<void>('setBackgroundColor', {
      'argb': color.toARGB32(),
    });
  } on MissingPluginException {
    // Keep alternate embedders and unit-test harnesses usable when the native
    // runner is not present.
  }
}
