/// Imports World layers into the Knowledge Base's shared asset store.
library;

import 'dart:io';

import 'package:dayseven/shared/world/domain/world_layer.dart';
import 'package:dayseven/shared/world/data/world_image_metadata_reader.dart';
import 'package:dayseven/shared/kb/bundle.dart';

/// A World layer is a data export, not a general-purpose picture.
const List<String> kWorldLayerExtensions = ['png', 'jpg', 'jpeg'];

/// The larger ceiling needed by high-resolution equirectangular maps.
const int kMaxWorldLayerBytes = 512 * 1024 * 1024;

/// Stores a layer image and records the metadata found in the stored copy.
///
/// The extension check, asset-id storage, and non-deleting clear behaviour
/// follow the settled rules in `timelines/map_renderer/map_upload.dart`:
/// validation belongs at import because a file can arrive renamed, references
/// store asset ids rather than paths, and clearing a layer never deletes the
/// asset file.
class WorldAssetRepository {
  WorldAssetRepository(this.kb);

  final KnowledgeBase kb;

  /// Validates and imports [source] as [kind], returning its new layer record.
  Future<WorldLayer> importLayer({
    required String id,
    required WorldLayerKind kind,
    required File source,
  }) async {
    // The picker is not a trust boundary. The extension gives an early,
    // friendly error; the encoded signature is validated below.
    final extension = source.path.toLowerCase().split('.').last;
    if (!kWorldLayerExtensions.contains(extension)) {
      throw const KbException('A World map has to be a PNG or JPEG.');
    }

    // Inspect before copying so a rejected projection never lands in the
    // bundle's asset directory.
    final sourceMetadata = await const WorldImageMetadataReader().read(source);
    final extensionMatches = switch (sourceMetadata.mediaType) {
      'image/png' => extension == 'png',
      'image/jpeg' => extension == 'jpg' || extension == 'jpeg',
      _ => false,
    };
    if (!extensionMatches) {
      throw const KbException(
        'The World map filename does not match its encoded image type.',
      );
    }
    if (!sourceMetadata.isEquirectangular) {
      throw KbException(
        'A World layer must be equirectangular (2:1). Found '
        '${sourceMetadata.width}×${sourceMetadata.height}; expected '
        '${sourceMetadata.height * 2}×${sourceMetadata.height}.',
      );
    }

    final assetId = await kb.importAsset(source, maxBytes: kMaxWorldLayerBytes);
    final storedMetadata = await const WorldImageMetadataReader().read(
      File(kb.assetPathFor(assetId)),
    );
    return WorldLayer(
      id: id,
      kind: kind,
      assetId: assetId,
      metadata: storedMetadata,
    );
  }
}
