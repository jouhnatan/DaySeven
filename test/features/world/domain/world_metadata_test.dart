import 'package:dayseven/features/world/domain/world_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('2:1 is equirectangular', () {
    const metadata = WorldMetadata(
      width: 4096,
      height: 2048,
      isGreyscale: true,
    );

    expect(metadata.isEquirectangular, isTrue);
  });

  test('a one-pixel 2:1 export is equirectangular', () {
    const metadata = WorldMetadata(
      width: 4097,
      height: 2048,
      isGreyscale: true,
    );

    expect(metadata.isEquirectangular, isTrue);
  });

  test('other dimensions are not equirectangular', () {
    const metadata = WorldMetadata(
      width: 4098,
      height: 2048,
      isGreyscale: true,
    );

    expect(metadata.isEquirectangular, isFalse);
  });

  test('optional metadata is omitted when empty', () {
    const metadata = WorldMetadata(
      width: 4096,
      height: 2048,
      isGreyscale: false,
    );

    final json = metadata.toJson();

    expect(json.containsKey('planetCode'), isFalse);
    expect(json.containsKey('textChunks'), isFalse);
    expect(WorldMetadata.fromJson(json).isGreyscale, isFalse);
  });
}
