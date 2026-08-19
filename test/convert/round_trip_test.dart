import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dayseven/convert/docx.dart';
import 'package:dayseven/convert/odt.dart';
import 'package:dayseven/domain/blocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A one-pixel PNG, so the image path is exercised with real bytes.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

BlockDocument sample() => BlockDocument(
  id: 'doc-1',
  title: 'Aldenmoor',
  blocks: [
    ParagraphBlock(
      id: 'b1',
      spans: const [
        TextSpanNode(text: 'The moor is '),
        TextSpanNode(text: 'wide', bold: true),
        TextSpanNode(text: ' and '),
        TextSpanNode(text: 'cold', italic: true),
        TextSpanNode(text: ', or so they '),
        TextSpanNode(text: 'said', strikethrough: true),
        TextSpanNode(text: ' '),
        TextSpanNode(text: 'say', underline: true),
        TextSpanNode(text: '.'),
      ],
    ),
    ParagraphBlock(
      id: 'b2',
      spans: const [
        TextSpanNode(text: 'Aldenmoor', color: '#8A3B12'),
        TextSpanNode(text: ' at dusk', highlight: '#F2E7C9'),
        TextSpanNode(text: ' in Georgia', font: 'Georgia'),
      ],
      align: BlockAlign.center,
      spaceBefore: 24,
    ),
    ParagraphBlock(
      id: 'b3',
      spans: const [TextSpanNode(text: 'Right aligned.')],
      align: BlockAlign.right,
    ),
    const ImageBlock(id: 'b4', assetId: 'img_1.png', caption: 'The east gate'),
  ],
);

Future<Uint8List?> readAsset(String assetId) async => _png;

/// Compares what the formats can carry: text, the six inline formats,
/// alignment, space before, and images with their captions. Block ids are
/// regenerated on import, so they are not part of the comparison.
void expectRoundTripped(BlockDocument original, BlockDocument restored) {
  expect(restored.blocks, hasLength(original.blocks.length));

  for (var i = 0; i < original.blocks.length; i++) {
    final a = original.blocks[i];
    final b = restored.blocks[i];

    expect(b.align, a.align, reason: 'block $i alignment');
    expect(
      b.spaceBefore,
      closeTo(a.spaceBefore, 0.5),
      reason: 'block $i space before',
    );

    if (a is ParagraphBlock) {
      expect(b, isA<ParagraphBlock>(), reason: 'block $i type');
      final restoredSpans = (b as ParagraphBlock).normalized().spans;
      final originalSpans = a.normalized().spans;

      expect(b.plainText, a.plainText, reason: 'block $i text');
      expect(
        restoredSpans,
        hasLength(originalSpans.length),
        reason: 'block $i span count',
      );
      for (var s = 0; s < originalSpans.length; s++) {
        final x = originalSpans[s];
        final y = restoredSpans[s];
        expect(y.text, x.text, reason: 'block $i span $s text');
        expect(y.bold, x.bold, reason: 'block $i span $s bold');
        expect(y.italic, x.italic, reason: 'block $i span $s italic');
        expect(
          y.strikethrough,
          x.strikethrough,
          reason: 'block $i span $s strikethrough',
        );
        expect(y.underline, x.underline, reason: 'block $i span $s underline');
        expect(y.color, x.color, reason: 'block $i span $s colour');
        expect(y.highlight, x.highlight, reason: 'block $i span $s highlight');
        expect(y.font, x.font, reason: 'block $i span $s font');
      }
    } else if (a is ImageBlock) {
      expect(b, isA<ImageBlock>(), reason: 'block $i type');
      expect((b as ImageBlock).caption, a.caption, reason: 'block $i caption');
    }
  }
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_convert_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('DOCX', () {
    test('exports and re-imports without losing formatting', () async {
      final original = sample();
      final file = File(p.join(temp.path, 'Aldenmoor.docx'));

      await exportDocx(document: original, target: file, readAsset: readAsset);
      expect(await file.exists(), isTrue);

      final imported = await importDocx(file);
      expectRoundTripped(original, imported.document);
      expect(
        imported.assets,
        hasLength(1),
        reason: 'the embedded image comes back out',
      );
      expect(imported.assets.values.single, _png);
    });

    test('writes a package Word will recognise', () async {
      final file = File(p.join(temp.path, 'Aldenmoor.docx'));
      await exportDocx(document: sample(), target: file, readAsset: readAsset);

      final names = ZipDecoder()
          .decodeBytes(await file.readAsBytes())
          .files
          .map((f) => f.name)
          .toSet();

      expect(names, contains('[Content_Types].xml'));
      expect(names, contains('_rels/.rels'));
      expect(names, contains('word/document.xml'));
      expect(names, contains('word/_rels/document.xml.rels'));
      expect(names.any((n) => n.startsWith('word/media/')), isTrue);
    });

    test('takes its title from the file name on import', () async {
      final file = File(p.join(temp.path, 'The Fen Road.docx'));
      await exportDocx(document: sample(), target: file, readAsset: readAsset);

      final imported = await importDocx(file);
      expect(imported.document.title, 'The Fen Road');
    });

    test('a file that is not a Word document is rejected clearly', () async {
      final file = File(p.join(temp.path, 'not-a-docx.docx'));
      await file.writeAsBytes(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile('hello.txt', 5, utf8.encode('hello'))),
        ),
      );

      expect(() => importDocx(file), throwsA(isA<FormatException>()));
    });
  });

  group('ODT', () {
    test('exports and re-imports without losing formatting', () async {
      final original = sample();
      final file = File(p.join(temp.path, 'Aldenmoor.odt'));

      await exportOdt(document: original, target: file, readAsset: readAsset);
      expect(await file.exists(), isTrue);

      final imported = await importOdt(file);
      expectRoundTripped(original, imported.document);
      expect(imported.assets, hasLength(1));
      expect(imported.assets.values.single, _png);
    });

    test('writes mimetype first and uncompressed, as ODF requires', () async {
      final file = File(p.join(temp.path, 'Aldenmoor.odt'));
      await exportOdt(document: sample(), target: file, readAsset: readAsset);

      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      expect(archive.files.first.name, 'mimetype');
      expect(
        utf8.decode(archive.files.first.content as List<int>),
        'application/vnd.oasis.opendocument.text',
      );

      final names = archive.files.map((f) => f.name).toSet();
      expect(names, contains('META-INF/manifest.xml'));
      expect(names, contains('content.xml'));
      expect(names.any((n) => n.startsWith('Pictures/')), isTrue);
    });

    test('a file that is not an ODF document is rejected clearly', () async {
      final file = File(p.join(temp.path, 'not-an-odt.odt'));
      await file.writeAsBytes(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile('hello.txt', 5, utf8.encode('hello'))),
        ),
      );

      expect(() => importOdt(file), throwsA(isA<FormatException>()));
    });
  });

  group('cross-format', () {
    test('a document exported to DOCX can be exported on to ODT', () async {
      final original = sample();
      final docx = File(p.join(temp.path, 'a.docx'));
      await exportDocx(document: original, target: docx, readAsset: readAsset);

      final viaDocx = await importDocx(docx);
      final odt = File(p.join(temp.path, 'a.odt'));
      await exportOdt(
        document: viaDocx.document,
        target: odt,
        readAsset: (id) async => viaDocx.assets[id],
      );

      final viaOdt = await importOdt(odt);
      expectRoundTripped(original, viaOdt.document);
    });
  });
}
