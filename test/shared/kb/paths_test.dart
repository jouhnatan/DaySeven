import 'package:dayseven/shared/kb/paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'path containment includes the item but not similarly named siblings',
    () {
      expect(isPathAtOrBelow('Characters', 'Characters'), isTrue);
      expect(
        isPathAtOrBelow('Characters/Houses/Vane.md', 'Characters'),
        isTrue,
      );
      expect(isPathAtOrBelow('Characters-old/Vane.md', 'Characters'), isFalse);
    },
  );

  test('moving a folder relocates every descendant and nothing else', () {
    expect(
      relocatePath('Houses/Vane.md', from: 'Houses', to: 'Characters/Houses'),
      'Characters/Houses/Vane.md',
    );
    expect(
      relocatePath('Places/Fen.md', from: 'Houses', to: 'Characters/Houses'),
      'Places/Fen.md',
    );
  });
}
