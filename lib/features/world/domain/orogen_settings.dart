/// The small set of settings owned by the World Orogen engine.
library;

import 'package:flutter/foundation.dart';

/// Typed settings for Orogen, kept separate from the world's raw engine map.
@immutable
class OrogenSettings {
  const OrogenSettings({this.planetCode, this.activeLayerId});

  /// The empty settings value used before Orogen has been configured.
  static const empty = OrogenSettings();

  final String? planetCode;
  final String? activeLayerId;

  Map<String, Object?> toJson() => {
    if (planetCode != null && planetCode!.isNotEmpty) 'planetCode': planetCode,
    if (activeLayerId != null && activeLayerId!.isNotEmpty)
      'activeLayerId': activeLayerId,
  };

  static OrogenSettings fromJson(Map<String, Object?> json) => OrogenSettings(
    planetCode: _nonEmpty(json['planetCode']),
    activeLayerId: _nonEmpty(json['activeLayerId']),
  );

  OrogenSettings copyWith({
    String? planetCode,
    bool clearPlanetCode = false,
    String? activeLayerId,
    bool clearActiveLayerId = false,
  }) => OrogenSettings(
    planetCode: clearPlanetCode ? null : (planetCode ?? this.planetCode),
    activeLayerId: clearActiveLayerId
        ? null
        : (activeLayerId ?? this.activeLayerId),
  );
}

String? _nonEmpty(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return value;
}
