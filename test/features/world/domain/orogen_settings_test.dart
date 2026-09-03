import 'package:dayseven/features/world/domain/orogen_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings survive a round trip', () {
    const settings = OrogenSettings(
      planetCode: 'abc123',
      activeLayerId: 'height-1',
    );

    final restored = OrogenSettings.fromJson(settings.toJson());

    expect(restored.planetCode, 'abc123');
    expect(restored.activeLayerId, 'height-1');
  });

  test('the empty default has no settings', () {
    expect(OrogenSettings.empty.planetCode, isNull);
    expect(OrogenSettings.empty.activeLayerId, isNull);
    expect(OrogenSettings.empty.toJson(), isEmpty);
    expect(OrogenSettings.fromJson({}).toJson(), isEmpty);
  });

  test('copyWith can clear nullable settings', () {
    const settings = OrogenSettings(
      planetCode: 'abc123',
      activeLayerId: 'height-1',
    );

    final cleared = settings.copyWith(
      clearPlanetCode: true,
      clearActiveLayerId: true,
    );

    expect(cleared.toJson(), isEmpty);
  });
}
