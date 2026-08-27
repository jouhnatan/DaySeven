/// Minimal widget harness for shell / workspace tests.
library;

import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [DsShell] inside a [MaterialApp] with [dsTheme].
///
/// [container] is provided via [UncontrolledProviderScope] so the same
/// Knowledge Base session can be shared between setup and the widget tree.
/// Calls [WidgetTester.pumpAndSettle] before returning.
Future<void> pumpDsShell(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dsTheme(),
        home: const DsShell(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
