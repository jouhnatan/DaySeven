import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'copyWith changes one format without rebuilding or losing the others',
    () {
      const original = TextSpanNode(
        text: 'Aldric',
        italic: true,
        color: '#112233',
        href: 'https://example.com',
      );

      final bold = original.copyWith(bold: true);
      final unlinked = bold.copyWith(href: (_) => null);

      expect(bold.bold, isTrue);
      expect(bold.italic, isTrue);
      expect(bold.color, '#112233');
      expect(bold.href, 'https://example.com');
      expect(unlinked.href, isNull);
      expect(unlinked.color, '#112233');
    },
  );
}
