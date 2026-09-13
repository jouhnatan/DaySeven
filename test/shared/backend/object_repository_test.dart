import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/shared/backend/object_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a missing object schema is told apart from a publish conflict', () {
    expect(
      isObjectsUnavailable(
        const PostgrestException(message: 'no table', code: 'PGRST205'),
      ),
      isTrue,
    );
    expect(
      isObjectsUnavailable(
        const PostgrestException(message: 'no function', code: 'PGRST202'),
      ),
      isTrue,
    );
    expect(
      isObjectsUnavailable(
        const PostgrestException(message: 'moved on', code: '40001'),
      ),
      isFalse,
    );
  });

  group('canonicalObjectHash', () {
    test('ignores key order at every depth', () {
      final a = <String, Object?>{
        'kind': 'world',
        'model': {
          'layers': [
            {'assetId': 'map.png', 'id': 'surface'},
          ],
          'sourceMapLayerId': 'surface',
        },
        'economy': {
          'resourceTypes': [
            {'name': 'Stone', 'id': 'stone'},
          ],
        },
      };
      final b = <String, Object?>{
        'economy': {
          'resourceTypes': [
            {'id': 'stone', 'name': 'Stone'},
          ],
        },
        'model': {
          'sourceMapLayerId': 'surface',
          'layers': [
            {'id': 'surface', 'assetId': 'map.png'},
          ],
        },
        'kind': 'world',
      };

      expect(canonicalObjectHash(a), canonicalObjectHash(b));
    });

    test('a changed value changes the hash', () {
      final base = <String, Object?>{'population': 100};
      final changed = <String, Object?>{'population': 101};
      expect(canonicalObjectHash(base), isNot(canonicalObjectHash(changed)));
    });
  });

  group('referencedByObject', () {
    test('finds asset ids at any depth and de-duplicates them', () {
      final repository = AssetRepository();
      final ids = repository.referencedByObject({
        'kind': 'world',
        'model': {
          'layers': [
            {'assetId': 'map.png'},
            {'assetId': 'relief.png'},
            {'name': 'no asset here'},
          ],
        },
        'economy': {
          'resourceNodes': [
            {'assetId': 'map.png'},
          ],
        },
      });

      expect(ids, {'map.png', 'relief.png'});
    });

    test('an object with no assets references nothing', () {
      expect(
        AssetRepository().referencedByObject({'kind': 'world', 'id': 'w1'}),
        isEmpty,
      );
    });
  });
}
