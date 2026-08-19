import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/theme.dart';
import 'package:dayseven/platform/install_location.dart';
import 'package:dayseven/sync/supabase.dart';
import 'package:dayseven/ui/shell/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabase();
  runApp(const ProviderScope(child: DaySevenApp()));
}

class DaySevenApp extends StatelessWidget {
  const DaySevenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DaySeven',
      debugShowCheckedModeBanner: false,
      theme: dsTheme(Brightness.light),
      darkTheme: dsTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const _Launch(),
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
      builder: (context) => AlertDialog(
        backgroundColor: colors.island,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(DsRadius.island),
          side: BorderSide(color: colors.border),
        ),
        content: Text(
          'DaySeven belongs in the Applications folder. '
          'Move it there to keep updates and permissions working.',
          style: aleo(size: 13, color: colors.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Continue', style: aleo(size: 13, color: colors.text)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const DsShell();
}
