/// Synchronises only the local image files referenced by shared documents.
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

  Iterable<String> referencedBy(BlockDocument document) => document.blocks
      .whereType<ImageBlock>()
      .map((block) => block.assetId)
      .where((id) => id.isNotEmpty)
      .toSet();

  Future<void> uploadReferenced({
    required KnowledgeBase kb,
    required BlockDocument document,
  }) async {
    for (final assetId in referencedBy(document)) {
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

  Future<void> downloadMissing({
    required KnowledgeBase kb,
    required BlockDocument document,
  }) async {
    for (final assetId in referencedBy(document)) {
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

final assetRepositoryProvider = Provider((ref) => AssetRepository());
