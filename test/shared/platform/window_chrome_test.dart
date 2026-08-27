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

      await tester.pumpWidget(app(CF.inset));
      await tester.pumpWidget(app(CF.paper));

      expect(calls, hasLength(2));
      expect(calls[0].method, 'setBackgroundColor');
      expect(calls[0].arguments, {'argb': CF.inset.toARGB32()});
      expect(calls[1].arguments, {'argb': CF.paper.toARGB32()});
    });
  });

  testWidgets('does not resend an unchanged background', (tester) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      const widget = WindowChromeSync(
        backgroundColor: CF.inset,
        child: SizedBox(),
      );

      await tester.pumpWidget(widget);
      await tester.pumpWidget(widget);

      expect(calls, hasLength(1));
    });
  });

  testWidgets('keeps the native chrome light when the system turns dark', (
    tester,
  ) async {
    await _withPlatform(TargetPlatform.macOS, () async {
      try {
        tester.platformDispatcher.platformBrightnessTestValue =
            Brightness.light;
        await tester.pumpWidget(
          MaterialApp(
            theme: dsTheme(),
            builder: (context, child) => WindowChromeSync(
              backgroundColor: context.ds.appBackground,
              child: child ?? const SizedBox.shrink(),
            ),
            home: const SizedBox(),
          ),
        );

        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        await tester.pumpAndSettle();

        // The interface has one palette, so the title bar the platform is
        // handed does not change when the system does. A dark title bar is not
        // something this application has, and the Windows runner decides
        // whether to use dark caption glyphs from this colour's luminance —
        // so sending a dark colour here is what would turn the chrome dark.
        expect(calls, hasLength(1));
        expect(calls.single.arguments, {'argb': CF.inset.toARGB32()});
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
