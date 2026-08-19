/// DOCX (Office Open XML) import and export.
///
/// Written directly against the zip container and `word/document.xml`, because
/// no Dart package round-trips DOCX: the available ones either fill templates
/// or extract plain text. Everything the block model can express — the six
/// inline formats, alignment, space before, images and their captions — is
/// mapped in both directions; anything else in an imported file is dropped,
/// which is the honest limit of a block-per-paragraph model.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

/// Marks a paragraph as an image caption, so a round-trip through Word keeps
/// the caption attached to its image.
const String _captionStyle = 'Caption';

const String _w =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const String _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const String _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const String _wp =
    'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing';
const String _pic = 'http://schemas.openxmlformats.org/drawingml/2006/picture';

/// An image pulled out of, or destined for, a document file.
class ConvertedAsset {
  const ConvertedAsset({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class ImportedDocument {
  const ImportedDocument({required this.document, required this.assets});

  final BlockDocument document;

  /// Images to be written into the Knowledge Base's `assets/` folder, keyed by
  /// the assetId the blocks refer to.
  final Map<String, Uint8List> assets;
}

// ------------------------------------------------------------------ import --

Future<ImportedDocument> importDocx(File file, {String? title}) async {
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  final documentXml = _findFile(archive, 'word/document.xml');
  if (documentXml == null) {
    throw const FormatException(
      'Not a Word document: word/document.xml is missing.',
    );
  }

  final relationships = _readRelationships(archive);
  final xml = XmlDocument.parse(utf8.decode(documentXml));
  final body = xml.findAllElements('body', namespaceUri: _w).firstOrNull;
  if (body == null) throw const FormatException('The document has no body.');

  final blocks = <Block>[];
  final assets = <String, Uint8List>{};

  for (final paragraph in body.childElements) {
    if (paragraph.localName != 'p') continue;

    final imageRelId = _imageRelIdIn(paragraph);
    if (imageRelId != null) {
      final target = relationships[imageRelId];
      final bytes = target == null
          ? null
          : _findFile(archive, 'word/${target.replaceFirst('/word/', '')}');
      if (target != null && bytes != null) {
        final assetId = '${newId()}${p.extension(target)}';
        assets[assetId] = Uint8List.fromList(bytes);
        blocks.add(
          ImageBlock(
            id: newId(),
            assetId: assetId,
            align: _alignOf(paragraph),
            spaceBefore: _spaceBeforeOf(paragraph),
          ),
        );
        continue;
      }
    }

    final spans = _spansOf(paragraph);
    final isCaption = _styleOf(paragraph) == _captionStyle;

    // A caption paragraph belongs to the image above it, not to the document.
    if (isCaption && blocks.isNotEmpty && blocks.last is ImageBlock) {
      final image = blocks.removeLast() as ImageBlock;
      blocks.add(image.copyWith(caption: spans.map((s) => s.text).join()));
      continue;
    }

    blocks.add(
      ParagraphBlock(
        id: newId(),
        spans: spans,
        align: _alignOf(paragraph),
        spaceBefore: _spaceBeforeOf(paragraph),
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

Map<String, String> _readRelationships(Archive archive) {
  final bytes = _findFile(archive, 'word/_rels/document.xml.rels');
  if (bytes == null) return const {};
  final xml = XmlDocument.parse(utf8.decode(bytes));
  return {
    for (final rel in xml.findAllElements('Relationship'))
      rel.getAttribute('Id')!: rel.getAttribute('Target')!,
  };
}

String? _imageRelIdIn(XmlElement paragraph) {
  for (final blip in paragraph.findAllElements('blip', namespaceUri: _a)) {
    final id = blip.getAttribute('embed', namespaceUri: _r);
    if (id != null) return id;
  }
  return null;
}

String? _styleOf(XmlElement paragraph) => paragraph
    .findElements('pPr', namespaceUri: _w)
    .expand((pPr) => pPr.findElements('pStyle', namespaceUri: _w))
    .map((e) => e.getAttribute('val', namespaceUri: _w))
    .firstOrNull;

BlockAlign _alignOf(XmlElement paragraph) {
  final value = paragraph
      .findElements('pPr', namespaceUri: _w)
      .expand((pPr) => pPr.findElements('jc', namespaceUri: _w))
      .map((e) => e.getAttribute('val', namespaceUri: _w))
      .firstOrNull;
  return switch (value) {
    'center' => BlockAlign.center,
    'right' || 'end' => BlockAlign.right,
    _ => BlockAlign.left,
  };
}

/// `w:spacing/@w:before` is in twentieths of a point; the block model stores
/// logical pixels, which at 96dpi is points times 4/3.
double _spaceBeforeOf(XmlElement paragraph) {
  final twips = paragraph
      .findElements('pPr', namespaceUri: _w)
      .expand((pPr) => pPr.findElements('spacing', namespaceUri: _w))
      .map((e) => e.getAttribute('before', namespaceUri: _w))
      .firstOrNull;
  final value = int.tryParse(twips ?? '');
  return value == null ? 0 : (value / 20) * 4 / 3;
}

List<TextSpanNode> _spansOf(XmlElement paragraph) {
  final spans = <TextSpanNode>[];

  for (final run in paragraph.findElements('r', namespaceUri: _w)) {
    final text = run
        .findElements('t', namespaceUri: _w)
        .map((t) => t.innerText)
        .join();
    final breaks = run.findElements('br', namespaceUri: _w).isNotEmpty
        ? '\n'
        : '';
    final content = '$text$breaks';
    if (content.isEmpty) continue;

    final rPr = run.findElements('rPr', namespaceUri: _w).firstOrNull;
    spans.add(
      TextSpanNode(
        text: content,
        bold: _onOff(rPr, 'b'),
        italic: _onOff(rPr, 'i'),
        strikethrough: _onOff(rPr, 'strike'),
        underline:
            rPr
                ?.findElements('u', namespaceUri: _w)
                .map((e) => e.getAttribute('val', namespaceUri: _w))
                .firstOrNull
                ?.let((v) => v != 'none') ??
            false,
        color: _hex(
          rPr
              ?.findElements('color', namespaceUri: _w)
              .map((e) => e.getAttribute('val', namespaceUri: _w))
              .firstOrNull,
        ),
        highlight: _hex(
          rPr
              ?.findElements('shd', namespaceUri: _w)
              .map((e) => e.getAttribute('fill', namespaceUri: _w))
              .firstOrNull,
        ),
        font: rPr
            ?.findElements('rFonts', namespaceUri: _w)
            .map((e) => e.getAttribute('ascii', namespaceUri: _w))
            .firstOrNull,
      ),
    );
  }
  return spans;
}

bool _onOff(XmlElement? rPr, String name) {
  final element = rPr?.findElements(name, namespaceUri: _w).firstOrNull;
  if (element == null) return false;
  final val = element.getAttribute('val', namespaceUri: _w);
  return val == null || val == '1' || val == 'true' || val == 'on';
}

String? _hex(String? value) {
  if (value == null || value.isEmpty) return null;
  if (value.toLowerCase() == 'auto') return null;
  return '#${value.replaceFirst('#', '').toUpperCase()}';
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

// ------------------------------------------------------------------ export --

Future<void> exportDocx({
  required BlockDocument document,
  required File target,
  required Future<Uint8List?> Function(String assetId) readAsset,
}) async {
  final archive = Archive();
  final images = <String, _EmbeddedImage>{};

  var imageNumber = 0;
  for (final block in document.blocks) {
    if (block is! ImageBlock) continue;
    final bytes = await readAsset(block.assetId);
    if (bytes == null) continue;
    imageNumber++;
    final extension = p.extension(block.assetId).isEmpty
        ? '.png'
        : p.extension(block.assetId);
    images[block.assetId] = _EmbeddedImage(
      relId: 'rId$imageNumber',
      name: 'image$imageNumber$extension',
      bytes: bytes,
    );
  }

  void add(String name, List<int> bytes) =>
      archive.addFile(ArchiveFile(name, bytes.length, bytes));

  add('[Content_Types].xml', utf8.encode(_contentTypes(images.values)));
  add('_rels/.rels', utf8.encode(_rootRels));
  add(
    'word/_rels/document.xml.rels',
    utf8.encode(_documentRels(images.values)),
  );
  add('word/document.xml', utf8.encode(_documentXml(document, images)));
  for (final image in images.values) {
    add('word/media/${image.name}', image.bytes);
  }

  await target.writeAsBytes(ZipEncoder().encode(archive));
}

class _EmbeddedImage {
  const _EmbeddedImage({
    required this.relId,
    required this.name,
    required this.bytes,
  });

  final String relId;
  final String name;
  final Uint8List bytes;
}

String _contentTypes(Iterable<_EmbeddedImage> images) {
  final extensions = {
    for (final image in images)
      p.extension(image.name).replaceFirst('.', '').toLowerCase(),
  };
  final defaults = StringBuffer();
  for (final ext in extensions) {
    final mime = switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'tif' || 'tiff' => 'image/tiff',
      _ => 'application/octet-stream',
    };
    defaults.write('<Default Extension="$ext" ContentType="$mime"/>');
  }

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '$defaults'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';
}

const String _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rIdDoc" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

String _documentRels(Iterable<_EmbeddedImage> images) {
  final buffer = StringBuffer();
  for (final image in images) {
    buffer.write(
      '<Relationship Id="${image.relId}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="media/${image.name}"/>',
    );
  }
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '$buffer</Relationships>';
}

String _documentXml(
  BlockDocument document,
  Map<String, _EmbeddedImage> images,
) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  builder.element(
    'w:document',
    nest: () {
      builder.attribute('xmlns:w', _w);
      builder.attribute('xmlns:r', _r);
      builder.attribute('xmlns:a', _a);
      builder.attribute('xmlns:wp', _wp);
      builder.attribute('xmlns:pic', _pic);

      builder.element(
        'w:body',
        nest: () {
          for (final block in document.blocks) {
            switch (block) {
              // A heading exports as a paragraph carrying its text. Native
              // heading styles are a later phase; this keeps the words.
              case TextBlock():
                _buildParagraph(builder, block);
              // Neither is a .docx concept; both export as their text so the
              // words survive a round trip through Word.
              case CodeBlock():
                _buildParagraph(
                  builder,
                  ParagraphBlock(
                    id: block.id,
                    spans: [TextSpanNode(text: block.text)],
                    align: block.align,
                    spaceBefore: block.spaceBefore,
                  ),
                );
              case DividerBlock():
                _buildParagraph(
                  builder,
                  ParagraphBlock(
                    id: block.id,
                    spans: const [TextSpanNode(text: '———')],
                    align: block.align,
                    spaceBefore: block.spaceBefore,
                  ),
                );
              case ImageBlock():
                final image = images[block.assetId];
                if (image != null) _buildImageParagraph(builder, block, image);
                if (block.caption.isNotEmpty) {
                  _buildCaption(builder, block);
                }
            }
          }
        },
      );
    },
  );
  return builder.buildDocument().toXmlString();
}

void _buildParagraphProperties(
  XmlBuilder builder,
  Block block, {
  String? style,
}) {
  if (style == null &&
      block.align == BlockAlign.left &&
      block.spaceBefore == 0) {
    return;
  }
  builder.element(
    'w:pPr',
    nest: () {
      if (style != null) {
        builder.element(
          'w:pStyle',
          nest: () => builder.attribute('w:val', style),
        );
      }
      if (block.spaceBefore > 0) {
        // Logical pixels back to twentieths of a point.
        final twips = (block.spaceBefore * 3 / 4 * 20).round();
        builder.element(
          'w:spacing',
          nest: () => builder.attribute('w:before', '$twips'),
        );
      }
      if (block.align != BlockAlign.left) {
        builder.element(
          'w:jc',
          nest: () => builder.attribute(
            'w:val',
            block.align == BlockAlign.center ? 'center' : 'right',
          ),
        );
      }
    },
  );
}

void _buildParagraph(XmlBuilder builder, TextBlock block) {
  builder.element(
    'w:p',
    nest: () {
      _buildParagraphProperties(builder, block);
      for (final span in block.spans) {
        _buildRun(builder, span);
      }
    },
  );
}

void _buildRun(XmlBuilder builder, TextSpanNode span) {
  builder.element(
    'w:r',
    nest: () {
      final hasFormat =
          span.bold ||
          span.italic ||
          span.strikethrough ||
          span.underline ||
          span.color != null ||
          span.highlight != null ||
          span.font != null;

      if (hasFormat) {
        builder.element(
          'w:rPr',
          nest: () {
            if (span.font != null) {
              builder.element(
                'w:rFonts',
                nest: () {
                  builder.attribute('w:ascii', span.font!);
                  builder.attribute('w:hAnsi', span.font!);
                },
              );
            }
            if (span.bold) builder.element('w:b');
            if (span.italic) builder.element('w:i');
            if (span.strikethrough) builder.element('w:strike');
            if (span.underline) {
              builder.element(
                'w:u',
                nest: () => builder.attribute('w:val', 'single'),
              );
            }
            if (span.color != null) {
              builder.element(
                'w:color',
                nest: () => builder.attribute(
                  'w:val',
                  span.color!.replaceFirst('#', ''),
                ),
              );
            }
            if (span.highlight != null) {
              // w:highlight only accepts named colours, so an arbitrary highlight
              // is written as paragraph shading instead.
              builder.element(
                'w:shd',
                nest: () {
                  builder.attribute('w:val', 'clear');
                  builder.attribute('w:color', 'auto');
                  builder.attribute(
                    'w:fill',
                    span.highlight!.replaceFirst('#', ''),
                  );
                },
              );
            }
          },
        );
      }

      builder.element(
        'w:t',
        nest: () {
          builder.attribute('xml:space', 'preserve');
          builder.text(span.text);
        },
      );
    },
  );
}

void _buildCaption(XmlBuilder builder, ImageBlock block) {
  builder.element(
    'w:p',
    nest: () {
      _buildParagraphProperties(builder, block, style: _captionStyle);
      _buildRun(builder, TextSpanNode(text: block.caption, italic: true));
    },
  );
}

void _buildImageParagraph(
  XmlBuilder builder,
  ImageBlock block,
  _EmbeddedImage image,
) {
  // A fixed display box: the block model does not record image dimensions, and
  // Word requires an extent.
  const widthEmu = 4572000; // 12cm
  const heightEmu = 3429000; // 9cm

  builder.element(
    'w:p',
    nest: () {
      _buildParagraphProperties(builder, block);
      builder.element(
        'w:r',
        nest: () {
          builder.element(
            'w:drawing',
            nest: () {
              builder.element(
                'wp:inline',
                nest: () {
                  builder.element(
                    'wp:extent',
                    nest: () {
                      builder.attribute('cx', '$widthEmu');
                      builder.attribute('cy', '$heightEmu');
                    },
                  );
                  builder.element(
                    'wp:docPr',
                    nest: () {
                      builder.attribute('id', '1');
                      builder.attribute('name', image.name);
                      if (block.caption.isNotEmpty) {
                        builder.attribute('descr', block.caption);
                      }
                    },
                  );
                  builder.element(
                    'a:graphic',
                    nest: () {
                      builder.element(
                        'a:graphicData',
                        nest: () {
                          builder.attribute('uri', _pic);
                          builder.element(
                            'pic:pic',
                            nest: () {
                              builder.element(
                                'pic:nvPicPr',
                                nest: () {
                                  builder.element(
                                    'pic:cNvPr',
                                    nest: () {
                                      builder.attribute('id', '0');
                                      builder.attribute('name', image.name);
                                    },
                                  );
                                  builder.element('pic:cNvPicPr');
                                },
                              );
                              builder.element(
                                'pic:blipFill',
                                nest: () {
                                  builder.element(
                                    'a:blip',
                                    nest: () => builder.attribute(
                                      'r:embed',
                                      image.relId,
                                    ),
                                  );
                                  builder.element(
                                    'a:stretch',
                                    nest: () => builder.element('a:fillRect'),
                                  );
                                },
                              );
                              builder.element(
                                'pic:spPr',
                                nest: () {
                                  builder.element(
                                    'a:xfrm',
                                    nest: () {
                                      builder.element(
                                        'a:off',
                                        nest: () {
                                          builder.attribute('x', '0');
                                          builder.attribute('y', '0');
                                        },
                                      );
                                      builder.element(
                                        'a:ext',
                                        nest: () {
                                          builder.attribute('cx', '$widthEmu');
                                          builder.attribute('cy', '$heightEmu');
                                        },
                                      );
                                    },
                                  );
                                  builder.element(
                                    'a:prstGeom',
                                    nest: () =>
                                        builder.attribute('prst', 'rect'),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}
