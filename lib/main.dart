import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/platform/app_profile.dart';

Future<void> _initCrdt() async {
  try {
    await RustLib.init();
  } catch (e, st) {
    developer.log(
      'CRDT native library unavailable: $e',
      error: e,
      stackTrace: st,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything reads Application Support: a second copy launched to hold
  // a second account needs its own directory, and its own signed-in session.
  final profile = await AppProfile.acquire(mode: profileModeFromEnvironment());
  await initSupabase(auth: profile.authOptions());
  await _initCrdt();
  runApp(
    ProviderScope(
      overrides: [appProfileProvider.overrideWithValue(profile)],
      child: const DaySevenApp(),
    ),
  );
}
