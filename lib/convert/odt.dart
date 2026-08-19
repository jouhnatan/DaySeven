/// ODT (OpenDocument Text) import and export.
///
/// Like the DOCX side, this is written directly against the zip container and
/// its XML parts. ODF keeps formatting in named automatic styles rather than
/// inline, so export generates one style per distinct format the document uses,
/// and import resolves style names back to formats.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../domain/blocks.dart';
import '../kb/bundle.dart';
import 'docx.dart' show ImportedDocument;

const String _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const String _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const String _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';
const String _fo =
    'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const String _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const String _xlink = 'http://www.w3.org/1999/xlink';
const String _svg = 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0';
const String _manifestNs = 'urn:oasis:names:tc:opendocument:xmlns:manifest:1.0';

/// The paragraph style DaySeven writes for image captions, matched on import.
const String _captionStyleName = 'DsCaption';

// ------------------------------------------------------------------ import --

Future<ImportedDocument> importOdt(File file, {String? title}) async {
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  final contentBytes = _findFile(archive, 'content.xml');
  if (contentBytes == null) {
    throw const FormatException(
      'Not an ODF text document: content.xml is missing.',
    );
  }

  final xml = XmlDocument.parse(utf8.decode(contentBytes));
  final paragraphStyles = _readParagraphStyles(xml);
  final textStyles = _readTextStyles(xml);

  final body = xml.findAllElements('text', namespaceUri: _office).firstOrNull;
  if (body == null) {
    throw const FormatException('The document has no text body.');
  }

  final blocks = <Block>[];
  final assets = <String, Uint8List>{};

  for (final element in body.childElements) {
    if (element.localName != 'p' && element.localName != 'h') continue;

    final styleName = element.getAttribute('style-name', namespaceUri: _text);
    final paragraphStyle =
        paragraphStyles[styleName] ?? const _ParagraphStyle();

    final frame = element
        .findElements('frame', namespaceUri: _draw)
        .firstOrNull;
    if (frame != null) {
      final image = frame
          .findElements('image', namespaceUri: _draw)
          .firstOrNull;
      final href = image?.getAttribute('href', namespaceUri: _xlink);
      final bytes = href == null ? null : _findFile(archive, href);
      if (href != null && bytes != null) {
        final assetId = '${newId()}${p.extension(href)}';
        assets[assetId] = Uint8List.fromList(bytes);
        blocks.add(
          ImageBlock(
            id: newId(),
            assetId: assetId,
            align: paragraphStyle.align,
            spaceBefore: paragraphStyle.spaceBefore,
          ),
        );
        continue;
      }
    }

    final spans = _spansOf(element, textStyles);

    if (styleName == _captionStyleName &&
        blocks.isNotEmpty &&
        blocks.last is ImageBlock) {
      final image = blocks.removeLast() as ImageBlock;
      blocks.add(image.copyWith(caption: spans.map((s) => s.text).join()));
      continue;
    }

    blocks.add(
      ParagraphBlock(
        id: newId(),
        spans: spans,
        align: paragraphStyle.align,
        spaceBefore: paragraphStyle.spaceBefore,
      ),
    );
  }

  return ImportedDocument(
    document: BlockDocument(
      id: newId(),
      title: title ?? p.basenameWithoutExtension(file.path),
      blocks: blocks.isEmpty
          ? [ParagraphBlock(id: newId(), spans: const [])]
          : blocks,
    ),
    assets: assets,
  );
}

List<int>? _findFile(Archive archive, String name) {
  for (final f in archive.files) {
    if (f.name == name) return f.content as List<int>;
  }
  return null;
}

class _ParagraphStyle {
  const _ParagraphStyle({this.align = BlockAlign.left, this.spaceBefore = 0});

  final BlockAlign align;
  final double spaceBefore;
}

Map<String, _ParagraphStyle> _readParagraphStyles(XmlDocument xml) {
  final out = <String, _ParagraphStyle>{};
  for (final style in xml.findAllElements('style', namespaceUri: _style)) {
    if (style.getAttribute('family', namespaceUri: _style) != 'paragraph') {
      continue;
    }
    final name = style.getAttribute('name', namespaceUri: _style);
    if (name == null) continue;

    final properties = style
        .findElements('paragraph-properties', namespaceUri: _style)
        .firstOrNull;
    out[name] = _ParagraphStyle(
      align: switch (properties?.getAttribute(
        'text-align',
        namespaceUri: _fo,
      )) {
        'center' => BlockAlign.center,
        'end' || 'right' => BlockAlign.right,
        _ => BlockAlign.left,
      },
      spaceBefore: _lengthToPixels(
        properties?.getAttribute('margin-top', namespaceUri: _fo),
      ),
    );
  }
  return out;
}

Map<String, TextSpanNode> _readTextStyles(XmlDocument xml) {
  final out = <String, TextSpanNode>{};
  for (final style in xml.findAllElements('style', namespaceUri: _style)) {
    if (style.getAttribute('family', namespaceUri: _style) != 'text') continue;
    final name = style.getAttribute('name', namespaceUri: _style);
    if (name == null) continue;

    final props = style
        .findElements('text-properties', namespaceUri: _style)
        .firstOrNull;
    out[name] = TextSpanNode(
      text: '',
      bold: props?.getAttribute('font-weight', namespaceUri: _fo) == 'bold',
      italic: props?.getAttribute('font-style', namespaceUri: _fo) == 'italic',
      strikethrough:
          (props?.getAttribute(
                'text-line-through-style',
                namespaceUri: _style,
              ) ??
              'none') !=
          'none',
      underline:
          (props?.getAttribute('text-underline-style', namespaceUri: _style) ??
              'none') !=
          'none',
      color: _hex(props?.getAttribute('color', namespaceUri: _fo)),
      highlight: _hex(
        props?.getAttribute('background-color', namespaceUri: _fo),
      ),
      font: props?.getAttribute('font-name', namespaceUri: _style),
    );
  }
  return out;
}

/// ODF lengths carry a unit. Only the ones a paragraph's space-before is
/// plausibly written in are handled; anything else reads as no spacing.
double _lengthToPixels(String? length) {
  if (length == null) return 0;
  final match = RegExp(r'^([\d.]+)([a-z]*)$').firstMatch(length.trim());
  if (match == null) return 0;
  final value = double.tryParse(match.group(1)!) ?? 0;
  return switch (match.group(2)) {
    'cm' => value * 96 / 2.54,
    'mm' => value * 96 / 25.4,
    'in' => value * 96,
    'pt' => value * 4 / 3,
    'px' || '' => value,
    _ => 0,
  };
}

String? _hex(String? value) {
  if (value == null || value.isEmpty || value == 'transparent') return null;
  final cleaned = value.replaceFirst('#', '');
  if (cleaned.length != 6) return null;
  return '#${cleaned.toUpperCase()}';
}

List<TextSpanNode> _spansOf(
  XmlElement paragraph,
  Map<String, TextSpanNode> textStyles,
) {
  final spans = <TextSpanNode>[];

  void walk(XmlNode node, TextSpanNode format) {
    for (final child in node.children) {
      if (child is XmlText) {
        if (child.value.isEmpty) continue;
        spans.add(format.copyWith(text: child.value));
      } else if (child is XmlElement) {
        switch (child.localName) {
          case 'span':
            final name = child.getAttribute('style-name', namespaceUri: _text);
            walk(child, textStyles[name] ?? format);
          case 's':
            // An explicit run of spaces.
            final count =
                int.tryParse(
                  child.getAttribute('c', namespaceUri: _text) ?? '1',
                ) ??
                1;
            spans.add(format.copyWith(text: ' ' * count));
          case 'tab':
            spans.add(format.copyWith(text: '\t'));
          case 'line-break':
            spans.add(format.copyWith(text: '\n'));
          default:
            walk(child, format);
        }
      }
    }
  }

  walk(paragraph, const TextSpanNode(text: ''));
  return spans;
}

// ------------------------------------------------------------------ export --

Future<void> exportOdt({
  required BlockDocument document,
  required File target,
  required Future<Uint8List?> Function(String assetId) readAsset,
}) async {
  final images = <String, String>{};
  final imageBytes = <String, Uint8List>{};

  var number = 0;
  for (final block in document.blocks) {
    if (block is! ImageBlock) continue;
    final bytes = await readAsset(block.assetId);
    if (bytes == null) continue;
    number++;
    final extension = p.extension(block.assetId).isEmpty
        ? '.png'
        : p.extension(block.assetId);
    final name = 'Pictures/image$number$extension';
    images[block.assetId] = name;
    imageBytes[name] = bytes;
  }

  final archive = Archive();

  // The mimetype entry must come first and be stored uncompressed for the file
  // to be recognised as ODF.
  final mimetype = utf8.encode('application/vnd.oasis.opendocument.text');
  archive.addFile(
    ArchiveFile('mimetype', mimetype.length, mimetype)
      ..compression = CompressionType.none,
  );

  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  add('META-INF/manifest.xml', utf8.encode(_manifest(imageBytes.keys)));
  add('styles.xml', utf8.encode(_stylesXml));
  add('content.xml', utf8.encode(_contentXml(document, images)));
  imageBytes.forEach((name, bytes) => add(name, bytes));

  await target.writeAsBytes(ZipEncoder().encode(archive));
}

String _manifest(Iterable<String> pictures) {
  final buffer = StringBuffer();
  for (final name in pictures) {
    final mime = switch (p.extension(name).toLowerCase()) {
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.gif' => 'image/gif',
      '.webp' => 'image/webp',
      '.tif' || '.tiff' => 'image/tiff',
      _ => 'application/octet-stream',
    };
    buffer.write(
      '<manifest:file-entry manifest:full-path="$name" manifest:media-type="$mime"/>',
    );
  }

  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<manifest:manifest xmlns:manifest="$_manifestNs" manifest:version="1.3">'
      '<manifest:file-entry manifest:full-path="/" '
      'manifest:media-type="application/vnd.oasis.opendocument.text"/>'
      '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>'
      '<manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>'
      '$buffer'
      '</manifest:manifest>';
}

const String _stylesXml =
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-styles xmlns:office="$_office" office:version="1.3"/>';

String _contentXml(BlockDocument document, Map<String, String> images) {
  // ODF holds formatting in named styles, so each distinct paragraph and text
  // format used by the document becomes one automatic style.
  final paragraphStyles = <String, Block>{};
  final textStyles = <String, TextSpanNode>{};

  String paragraphStyleFor(Block block) {
    final key = 'P_${block.align.name}_${block.spaceBefore.toStringAsFixed(2)}';
    paragraphStyles.putIfAbsent(key, () => block);
    return key;
  }

  String? textStyleFor(TextSpanNode span) {
    if (!span.bold &&
        !span.italic &&
        !span.strikethrough &&
        !span.underline &&
        span.color == null &&
        span.highlight == null &&
        span.font == null) {
      return null;
    }
    final key =
        'T_${span.bold}_${span.italic}_${span.strikethrough}_'
        '${span.underline}_${span.color}_${span.highlight}_${span.font}';
    final safe = key.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    textStyles.putIfAbsent(safe, () => span);
    return safe;
  }

  // A first pass registers the styles the body will refer to.
  final bodyPlan = <_PlannedBlock>[];
  for (final block in document.blocks) {
    switch (block) {
      case ParagraphBlock():
        bodyPlan.add(
          _PlannedBlock(
            block: block,
            paragraphStyle: paragraphStyleFor(block),
            textStyleNames: [for (final s in block.spans) textStyleFor(s)],
          ),
        );
      case ImageBlock():
        bodyPlan.add(
          _PlannedBlock(
            block: block,
            paragraphStyle: paragraphStyleFor(block),
            textStyleNames: const [],
          ),
        );
    }
  }

  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'office:document-content',
    nest: () {
      builder.attribute('xmlns:office', _office);
      builder.attribute('xmlns:text', _text);
      builder.attribute('xmlns:style', _style);
      builder.attribute('xmlns:fo', _fo);
      builder.attribute('xmlns:draw', _draw);
      builder.attribute('xmlns:xlink', _xlink);
      builder.attribute('xmlns:svg', _svg);
      builder.attribute('office:version', '1.3');

      builder.element(
        'office:automatic-styles',
        nest: () {
          paragraphStyles.forEach((name, block) {
            builder.element(
              'style:style',
              nest: () {
                builder.attribute('style:name', name);
                builder.attribute('style:family', 'paragraph');
                builder.element(
                  'style:paragraph-properties',
                  nest: () {
                    builder.attribute('fo:text-align', switch (block.align) {
                      BlockAlign.left => 'start',
                      BlockAlign.center => 'center',
                      BlockAlign.right => 'end',
                    });
                    if (block.spaceBefore > 0) {
                      builder.attribute(
                        'fo:margin-top',
                        '${(block.spaceBefore * 3 / 4).toStringAsFixed(2)}pt',
                      );
                    }
                  },
                );
              },
            );
          });

          // The caption style, so an exported caption comes back as a caption.
          builder.element(
            'style:style',
            nest: () {
              builder.attribute('style:name', _captionStyleName);
              builder.attribute('style:family', 'paragraph');
              builder.element(
                'style:text-properties',
                nest: () => builder.attribute('fo:font-style', 'italic'),
              );
            },
          );

          textStyles.forEach((name, span) {
            builder.element(
              'style:style',
              nest: () {
                builder.attribute('style:name', name);
                builder.attribute('style:family', 'text');
                builder.element(
                  'style:text-properties',
                  nest: () {
                    if (span.bold) builder.attribute('fo:font-weight', 'bold');
                    if (span.italic) {
                      builder.attribute('fo:font-style', 'italic');
                    }
                    if (span.strikethrough) {
                      builder.attribute(
                        'style:text-line-through-style',
                        'solid',
                      );
                    }
                    if (span.underline) {
                      builder.attribute('style:text-underline-style', 'solid');
                    }
                    if (span.color != null) {
                      builder.attribute('fo:color', span.color!);
                    }
                    if (span.highlight != null) {
                      builder.attribute('fo:background-color', span.highlight!);
                    }
                    if (span.font != null) {
                      builder.attribute('style:font-name', span.font!);
                    }
                  },
                );
              },
            );
          });
        },
      );

      builder.element(
        'office:body',
        nest: () {
          builder.element(
            'office:text',
            nest: () {
              for (final planned in bodyPlan) {
                switch (planned.block) {
                  case final ParagraphBlock block:
                    builder.element(
                      'text:p',
                      nest: () {
                        builder.attribute(
                          'text:style-name',
                          planned.paragraphStyle,
                        );
                        for (var i = 0; i < block.spans.length; i++) {
                          final span = block.spans[i];
                          final styleName = planned.textStyleNames[i];
                          if (styleName == null) {
                            builder.text(span.text);
                          } else {
                            builder.element(
                              'text:span',
                              nest: () {
                                builder.attribute('text:style-name', styleName);
                                builder.text(span.text);
                              },
                            );
                          }
                        }
                      },
                    );
                  case final ImageBlock block:
                    final href = images[block.assetId];
                    if (href != null) {
                      builder.element(
                        'text:p',
                        nest: () {
                          builder.attribute(
                            'text:style-name',
                            planned.paragraphStyle,
                          );
                          builder.element(
                            'draw:frame',
                            nest: () {
                              builder.attribute('draw:name', p.basename(href));
                              builder.attribute('svg:width', '12cm');
                              builder.attribute('svg:height', '9cm');
                              builder.element(
                                'draw:image',
                                nest: () {
                                  builder.attribute('xlink:href', href);
                                  builder.attribute('xlink:type', 'simple');
                                  builder.attribute('xlink:show', 'embed');
                                  builder.attribute('xlink:actuate', 'onLoad');
                                },
                              );
                            },
                          );
                        },
                      );
                    }
                    if (block.caption.isNotEmpty) {
                      builder.element(
                        'text:p',
                        nest: () {
                          builder.attribute(
                            'text:style-name',
                            _captionStyleName,
                          );
                          builder.text(block.caption);
                        },
                      );
                    }
                }
              }
            },
          );
        },
      );
    },
  );

  return builder.buildDocument().toXmlString();
}

class _PlannedBlock {
  const _PlannedBlock({
    required this.block,
    required this.paragraphStyle,
    required this.textStyleNames,
  });

  final Block block;
  final String paragraphStyle;
  final List<String?> textStyleNames;
}
