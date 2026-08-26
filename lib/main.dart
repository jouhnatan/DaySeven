import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';

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
  await initSupabase();
  await _initCrdt();
  runApp(const ProviderScope(child: DaySevenApp()));
}
