/// Presentation layer Riverpod providers for keybind access.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/core/keybinds/data/keybind_hash_map.dart';

/// Global provider for the application keybind hash map.
final keybindHashMapProvider = Provider<KeybindHashMap>((ref) {
  return KeybindHashMap.instance;
});
