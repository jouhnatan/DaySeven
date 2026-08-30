import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'macos_lights_controller.dart';
import 'traffic_lights_offset.dart';

/// A widget that synchronizes the macOS window traffic lights positioning on mount.
class MacosLightsSync extends StatefulWidget {
  const MacosLightsSync({
    required this.child,
    this.offset = TrafficLightsOffset.standard,
    this.controller,
    super.key,
  });

  final Widget child;
  final TrafficLightsOffset offset;
  final MacosLightsController? controller;

  @override
  State<MacosLightsSync> createState() => _MacosLightsSyncState();
}

class _MacosLightsSyncState extends State<MacosLightsSync> {
  late MacosLightsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? const MacosLightsController();
    _applyOffset();
  }

  @override
  void didUpdateWidget(MacosLightsSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _controller = widget.controller ?? const MacosLightsController();
    }
    if (widget.offset != oldWidget.offset) {
      _applyOffset();
    }
  }

  void _applyOffset() {
    if (defaultTargetPlatform != TargetPlatform.macOS) return;
    unawaited(_controller.setOffset(widget.offset));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
