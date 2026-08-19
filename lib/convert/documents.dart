/// Importing and exporting whole documents against a Knowledge Base.
///
/// The format converters deal in bytes and blocks; this puts the result in the
/// right place — images into the bundle's `assets/` folder, the document into
/// `documents/` — so the rest of the app only ever sees a Knowledge Base path.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../domain/blocks.dart';
import '../kb/bundle.dart';
import 'docx.dart';
import 'odt.dart';

/// The document formats DaySeven reads and writes.
enum DocumentFormat { docx, odt }

DocumentFormat? formatOf(String path) =>
    switch (p.extension(path).toLowerCase()) {
      '.docx' => DocumentFormat.docx,
      '.odt' => DocumentFormat.odt,
      _ => null,
    };

const List<String> kImportExtensions = ['docx', 'odt'];

/// Imports [source] into [kb], writing its images into the bundle and the
/// document into [folderRelativePath]. Returns the new document's path.
Future<String> importDocumentInto(
  KnowledgeBase kb,
  File source, {
  String folderRelativePath = '',
}) async {
  final format = formatOf(source.path);
  if (format == null) {
    throw const FormatException('DaySeven imports .docx and .odt documents.');
  }

  final imported = switch (format) {
    DocumentFormat.docx => await importDocx(source),
    DocumentFormat.odt => await importOdt(source),
  };

  // Write the images first, so no block ever points at a file that is not there.
  await Directory(kb.assetsPath).create(recursive: true);
  for (final entry in imported.assets.entries) {
    await File(p.join(kb.assetsPath, entry.key)).writeAsBytes(entry.value);
  }

  final relativePath = await kb.createDocument(
    title: imported.document.title,
    folderRelativePath: folderRelativePath,
  );
  await kb.writeDocument(relativePath, imported.document);
  return relativePath;
}

/// Exports [document] to [target], in the format implied by its extension.
Future<void> exportDocumentTo(
  KnowledgeBase kb,
  BlockDocument document,
  File target,
) async {
  final format = formatOf(target.path);
  if (format == null) {
    throw const FormatException('DaySeven exports .docx and .odt documents.');
  }

  Future<Uint8List?> readAsset(String assetId) async {
    final file = File(kb.assetPathFor(assetId));
    return await file.exists() ? await file.readAsBytes() : null;
  }

  switch (format) {
    case DocumentFormat.docx:
      await exportDocx(
        document: document,
        target: target,
        readAsset: readAsset,
      );
    case DocumentFormat.odt:
      await exportOdt(document: document, target: target, readAsset: readAsset);
  }
}
