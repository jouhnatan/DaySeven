/// The MaterialApp and the first-run check that runs behind it.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/shared/platform/install_location.dart';
import 'package:dayseven/shared/platform/window_chrome.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DaySevenApp extends StatelessWidget {
  const DaySevenApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<DsAppSettings>(
    valueListenable: DsGlobalSettings.listenable,
    builder: (context, settings, _) => MaterialApp(
      title: 'DaySeven',
      debugShowCheckedModeBanner: false,
      // One theme. The system is light and has no dark variant, so the
      // window chrome the native runners are handed is always a light one.
      theme: dsTheme(settings: settings),
      builder: (context, child) => WindowChromeSync(
        backgroundColor: context.ds.appBackground,
        child: child ?? const SizedBox.shrink(),
      ),
      // Rebuild the existing launch subtree for every global setting, even
      // when a future setting is not represented by ThemeData.
      home: _Launch(),
    ),
  );
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
