import 'package:dayseven/shared/platform/window_chrome.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dayseven/window_chrome');
  final calls = <MethodCall>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('sends the initial background and live color changes', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      Widget app(Color color) =>
          WindowChromeSync(backgroundColor: color, child: const SizedBox());

      await tester.pumpWidget(app(const Color(0xFFE8E9EC)));
      await tester.pumpWidget(app(const Color(0xFF121317)));

      expect(calls, hasLength(2));
      expect(calls[0].method, 'setBackgroundColor');
      expect(calls[0].arguments, {'argb': 0xFFE8E9EC});
      expect(calls[1].arguments, {'argb': 0xFF121317});
    });
  });

  testWidgets('does not resend an unchanged background', (tester) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      const widget = WindowChromeSync(
        backgroundColor: Color(0xFFE8E9EC),
        child: SizedBox(),
      );

      await tester.pumpWidget(widget);
      await tester.pumpWidget(widget);

      expect(calls, hasLength(1));
    });
  });

  testWidgets('follows live MaterialApp system brightness changes', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      try {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: Brightness.light,
              extensions: const [DsColors.light],
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              extensions: const [DsColors.dark],
            ),
            themeMode: ThemeMode.system,
            builder: (context, child) => WindowChromeSync(
              backgroundColor: context.ds.appBackground,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const SizedBox(),
          ),
        );

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();

        expect(calls, hasLength(2));
        expect(calls[0].arguments, {'argb': 0xFFE8E9EC});
        expect(calls[1].arguments, {'argb': 0xFF121317});
      } finally {
        tester.platformDispatcher.clearPlatformBrightnessTestValue();
      }
    });
  });

  testWidgets('does not invoke native chrome on unsupported platforms', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.android, () async {
      await tester.pumpWidget(
        const WindowChromeSync(
          backgroundColor: Color(0xFFE8E9EC),
          child: SizedBox(),
        ),
      );

      expect(calls, isEmpty);
    });
  });
}

Future<void> _withPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}
