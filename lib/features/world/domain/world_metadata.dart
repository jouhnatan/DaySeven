/// Metadata learned while reading a World image.
library;

import 'package:flutter/foundation.dart';

/// The dimensions and text carried by an imported PNG.
@immutable
class WorldMetadata {
  const WorldMetadata({
    required this.width,
    required this.height,
    required this.isGreyscale,
    this.planetCode,
    this.textChunks = const {},
  });

  final int width;
  final int height;
  final bool isGreyscale;
  final String? planetCode;
  final Map<String, String> textChunks;

  /// Whether the image is a 2:1 equirectangular export, allowing one pixel of
  /// rounding or export drift at either edge.
  bool get isEquirectangular => (width - (height * 2)).abs() <= 1;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'isGreyscale': isGreyscale,
    if (planetCode != null && planetCode!.isNotEmpty) 'planetCode': planetCode,
    if (textChunks.isNotEmpty) 'textChunks': textChunks,
  };

  static WorldMetadata fromJson(Map<String, Object?> json) => WorldMetadata(
    width: _int(json['width']) ?? 0,
    height: _int(json['height']) ?? 0,
    isGreyscale: json['isGreyscale'] == true,
    planetCode: _nonEmpty(json['planetCode']),
    textChunks: _stringMap(json['textChunks']),
  );
}

String? _nonEmpty(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return value;
}

Map<String, String> _stringMap(Object? value) {
  if (value is! Map) return <String, String>{};
  return {
    for (final entry in value.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

int? _int(Object? value) => switch (value) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};
