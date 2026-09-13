/// Synchronises the local image files referenced by shared documents and
/// Knowledge Base objects.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class AssetRepository {
  AssetRepository({
    this.clientOverride,
    this.requestTimeout = kSupabaseStorageRequestTimeout,
  });

  static const _bucket = 'kb-assets';
  final SupabaseClient? clientOverride;
  final Duration requestTimeout;

  SupabaseClient get client => clientOverride ?? supabase;

  /// Document assets are image blocks.
  Iterable<String> referencedBy(BlockDocument document) => document.blocks
      .whereType<ImageBlock>()
      .map((block) => block.assetId)
      .where((id) => id.isNotEmpty)
      .toSet();

  /// Object assets are any `assetId` value in the object JSON. The `.unearth`
  /// envelope states assets by id — a World layer's map, today — and the
  /// convention is old enough that a recursive walk is the honest reader: a
  /// new kind gets its assets synced without this file learning its schema.
  Iterable<String> referencedByObject(Object? json) =>
      _assetIdsIn(json).toSet();

  Future<void> uploadReferenced({
    required KnowledgeBase kb,
    required BlockDocument document,
  }) => uploadReferencedAssets(kb: kb, assetIds: referencedBy(document));

  Future<void> downloadMissing({
    required KnowledgeBase kb,
    required BlockDocument document,
  }) => downloadMissingAssets(kb: kb, assetIds: referencedBy(document));

  Future<void> uploadReferencedObject({
    required KnowledgeBase kb,
    required Object? json,
  }) => uploadReferencedAssets(kb: kb, assetIds: referencedByObject(json));

  Future<void> downloadMissingObject({
    required KnowledgeBase kb,
    required Object? json,
  }) => downloadMissingAssets(kb: kb, assetIds: referencedByObject(json));

  Future<void> uploadReferencedAssets({
    required KnowledgeBase kb,
    required Iterable<String> assetIds,
  }) async {
    for (final assetId in assetIds) {
      final file = File(kb.assetPathFor(assetId));
      if (!await file.exists()) {
        throw KbException('The image asset "$assetId" is missing.');
      }
      try {
        await client.storage
            .from(_bucket)
            .upload(
              '${kb.manifest.kbId}/$assetId',
              file,
              fileOptions: FileOptions(contentType: _mimeType(assetId)),
            )
            .timeout(requestTimeout);
      } on StorageException catch (error) {
        // Asset IDs are immutable UUID filenames. A conflict means this exact
        // asset was already uploaded by an earlier revision.
        if (error.statusCode != '409') rethrow;
      }
    }
  }

  Future<void> downloadMissingAssets({
    required KnowledgeBase kb,
    required Iterable<String> assetIds,
  }) async {
    for (final assetId in assetIds) {
      final file = File(kb.assetPathFor(assetId));
      if (await file.exists()) continue;
      final bytes = await client.storage
          .from(_bucket)
          .download('${kb.manifest.kbId}/$assetId')
          .timeout(requestTimeout);
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
  }

  String _mimeType(String assetId) =>
      switch (p.extension(assetId).toLowerCase()) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.gif' => 'image/gif',
        '.webp' => 'image/webp',
        '.tif' || '.tiff' => 'image/tiff',
        _ => 'image/png',
      };
}

Iterable<String> _assetIdsIn(Object? value) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == 'assetId' && entry.value is String) {
        final id = entry.value! as String;
        if (id.isNotEmpty) yield id;
        continue;
      }
      yield* _assetIdsIn(entry.value);
    }
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      yield* _assetIdsIn(item);
    }
  }
}

final assetRepositoryProvider = Provider((ref) => AssetRepository());
