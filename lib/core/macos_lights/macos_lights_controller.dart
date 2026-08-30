import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'traffic_lights_offset.dart';

const MethodChannel _defaultChannel = MethodChannel('dayseven/macos_lights');

/// Controller for adjusting macOS window traffic lights (close, minimize, zoom).
class MacosLightsController {
  const MacosLightsController({
    this.channel = _defaultChannel,
  });

  final MethodChannel channel;

  /// Applies the specified [offset] to macOS traffic lights.
  ///
  /// If running on a non-macOS platform or in unit tests where the channel is
  /// not registered, this safely no-ops without throwing errors.
  Future<void> setOffset([
    TrafficLightsOffset offset = TrafficLightsOffset.standard,
  ]) async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    try {
      await channel.invokeMethod<void>('setOffset', offset.toMap());
    } on MissingPluginException {
      // Platform channel not available in test or non-runner environments.
    } on PlatformException catch (e) {
      debugPrint('MacosLightsController.setOffset failed: $e');
    }
  }

  /// Resets macOS traffic light positions to their default native placement.
  Future<void> resetOffset() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    try {
      await channel.invokeMethod<void>('resetOffset');
    } on MissingPluginException {
      // Safely ignore missing handler.
    } on PlatformException catch (e) {
      debugPrint('MacosLightsController.resetOffset failed: $e');
    }
  }

  /// Retrieves the current traffic light offset from the native macOS host, if available.
  Future<TrafficLightsOffset?> getOffset() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return null;
    }

    try {
      final result = await channel.invokeMapMethod<String, dynamic>('getOffset');
      if (result == null) return null;
      final x = (result['x'] as num?)?.toDouble() ?? TrafficLightsOffset.defaultX;
      final y = (result['y'] as num?)?.toDouble() ?? TrafficLightsOffset.defaultY;
      return TrafficLightsOffset(x: x, y: y);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('MacosLightsController.getOffset failed: $e');
      return null;
    }
  }
}
