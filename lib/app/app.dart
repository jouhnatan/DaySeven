/// The MaterialApp and the first-run check that runs behind it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/view.dart';
import 'package:dayseven/features/gradient_background/ui/gradient_background.dart';
import 'package:dayseven/shared/platform/install_location.dart';
import 'package:dayseven/shared/platform/window_chrome.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DaySevenApp extends ConsumerWidget {
  const DaySevenApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);

    return ValueListenableBuilder<DsAppSettings>(
      valueListenable: DsGlobalSettings.listenable,
      builder: (context, settings, _) => MaterialApp(
        title: 'DaySeven',
        debugShowCheckedModeBanner: false,
        theme: dsTheme(Brightness.light, settings: settings),
        darkTheme: dsTheme(Brightness.dark, settings: settings),
        themeMode: ThemeMode.system,
        builder: (context, child) => WindowChromeSync(
          backgroundColor:
              view == DsView.home || settings.gradientBackgroundEnabled
              ? gradientShellBackground(Theme.of(context).brightness)
              : context.ds.appBackground,
          child: child ?? const SizedBox.shrink(),
        ),
        // Rebuild the existing launch subtree for every global setting, even
        // when a future setting is not represented by ThemeData.
        home: _Launch(),
      ),
    );
  }
}

class _Launch extends StatefulWidget {
  const _Launch();

  @override
  State<_Launch> createState() => _LaunchState();
}

class _LaunchState extends State<_Launch> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _warnIfMisplaced());
  }

  Future<void> _warnIfMisplaced() async {
    final location = checkInstallLocation();
    if (location.isCorrect || !mounted) return;

    final colors = context.ds;
    await showDialog<void>(
      context: context,
      builder: (context) => DsDialog(
        actions: [
          DsDialogAction(
            label: 'Continue',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
        children: [
          Text(
            'DaySeven belongs in the Applications folder. '
            'Move it there to keep updates and permissions working.',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const DsShell();
}
