import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/core/macos_lights/macos_lights.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrafficLightsOffset', () {
    test('standard has expected default offsets', () {
      expect(TrafficLightsOffset.defaultX, 20.0);
      expect(TrafficLightsOffset.defaultY, 18.0);
      expect(TrafficLightsOffset.standard.x, 20.0);
      expect(TrafficLightsOffset.standard.y, 18.0);
    });

    test('supports custom offsets', () {
      const offset = TrafficLightsOffset(x: 25.0, y: 30.0);
      expect(offset.x, 25.0);
      expect(offset.y, 30.0);
    });

    test('equality and hashCode work as value objects', () {
      const a = TrafficLightsOffset(x: 15.0, y: 22.0);
      const b = TrafficLightsOffset(x: 15.0, y: 22.0);
      const c = TrafficLightsOffset(x: 15.0, y: 23.0);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toMap converts to map correctly', () {
      const offset = TrafficLightsOffset(x: 12.5, y: 16.5);
      expect(offset.toMap(), {'x': 12.5, 'y': 16.5});
    });

    test('toString formats cleanly', () {
      const offset = TrafficLightsOffset(x: 20.0, y: 18.0);
      expect(offset.toString(), 'TrafficLightsOffset(x: 20.0, y: 18.0)');
    });
  });

  group('MacosLightsController', () {
    late List<MethodCall> methodCalls;
    const channel = MethodChannel('dayseven/macos_lights');

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        methodCalls.add(call);
        if (call.method == 'getOffset') {
          return {'x': 22.0, 'y': 19.0};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('setOffset invokes method channel on macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const controller = MacosLightsController(channel: channel);
        await controller.setOffset(const TrafficLightsOffset(x: 24.0, y: 20.0));

        expect(methodCalls, hasLength(1));
        expect(methodCalls.first.method, 'setOffset');
        expect(methodCalls.first.arguments, {'x': 24.0, 'y': 20.0});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('setOffset no-ops on non-macOS platforms', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        const controller = MacosLightsController(channel: channel);
        await controller.setOffset(const TrafficLightsOffset(x: 24.0, y: 20.0));

        expect(methodCalls, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('resetOffset invokes resetOffset on macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const controller = MacosLightsController(channel: channel);
        await controller.resetOffset();

        expect(methodCalls, hasLength(1));
        expect(methodCalls.first.method, 'resetOffset');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('getOffset returns offset on macOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const controller = MacosLightsController(channel: channel);
        final offset = await controller.getOffset();

        expect(methodCalls, hasLength(1));
        expect(methodCalls.first.method, 'getOffset');
        expect(offset, equals(const TrafficLightsOffset(x: 22.0, y: 19.0)));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('MacosLightsSync', () {
    late List<MethodCall> methodCalls;
    const channel = MethodChannel('dayseven/macos_lights');

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        methodCalls.add(call);
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    testWidgets('applies offset on macOS when mounted', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const controller = MacosLightsController(channel: channel);
        await tester.pumpWidget(
          const MacosLightsSync(
            controller: controller,
            offset: TrafficLightsOffset(x: 20.0, y: 18.0),
            child: SizedBox.shrink(),
          ),
        );
        await tester.pumpAndSettle();

        expect(methodCalls, hasLength(1));
        expect(methodCalls.first.method, 'setOffset');
        expect(methodCalls.first.arguments, {'x': 20.0, 'y': 18.0});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('updates offset when widget updates with new offset', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const controller = MacosLightsController(channel: channel);
        await tester.pumpWidget(
          const MacosLightsSync(
            controller: controller,
            offset: TrafficLightsOffset(x: 20.0, y: 18.0),
            child: SizedBox.shrink(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.pumpWidget(
          const MacosLightsSync(
            controller: controller,
            offset: TrafficLightsOffset(x: 28.0, y: 24.0),
            child: SizedBox.shrink(),
          ),
        );
        await tester.pumpAndSettle();

        expect(methodCalls, hasLength(2));
        expect(methodCalls.last.arguments, {'x': 28.0, 'y': 24.0});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
