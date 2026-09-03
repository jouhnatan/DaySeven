/// Loads bounded World textures and owns their native image handles.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'world_image_decoder.dart';

/// Acquires one World layer texture at a time and disposes replaced images.
class GlobeTextureLoader extends ChangeNotifier {
  ui.Image? _texture;
  String? _currentAssetId;
  String? _loadingAssetId;
  bool _isLoading = false;
  bool _disposed = false;
  int _loadGeneration = 0;

  ui.Image? get texture => _texture;
  String? get currentAssetId => _currentAssetId;
  bool get isLoading => _isLoading;

  /// Loads [assetPath] through the World decoder, reusing the current image
  /// when it already represents [assetId].
  Future<void> loadAsset(String assetPath, {required String assetId}) async {
    if (_disposed) return;
    if (assetId == _currentAssetId && _texture != null) return;
    if (assetId == _loadingAssetId) return;

    final generation = ++_loadGeneration;
    _loadingAssetId = assetId;
    _isLoading = true;
    notifyListeners();

    try {
      final bytes = await File(assetPath).readAsBytes();
      final decoded = await WorldImageDecoder.decode(
        bytes,
        target: WorldImageDecodeTarget.globeTexture,
      );

      if (_disposed || generation != _loadGeneration) {
        decoded.dispose();
        return;
      }

      final previous = _texture;
      _texture = decoded;
      _currentAssetId = assetId;
      previous?.dispose();
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loadingAssetId = null;
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Drops the reference without deleting the asset from the Knowledge Base.
  void clear() {
    if (_disposed) return;
    _loadGeneration++;
    _loadingAssetId = null;
    _isLoading = false;
    _currentAssetId = null;
    final previous = _texture;
    _texture = null;
    previous?.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _loadGeneration++;
    _loadingAssetId = null;
    _isLoading = false;
    _currentAssetId = null;
    _texture?.dispose();
    _texture = null;
    super.dispose();
  }
}
