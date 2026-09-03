/// Reads the small, useful parts of a PNG without decoding its image data.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/features/world/domain/world_metadata.dart';

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
const _maxChunks = 1000;
const _maxTextChunkBytes = 1024 * 1024;

/// Raised when a PNG cannot be inspected for its metadata.
class PngMetadataException implements Exception {
  const PngMetadataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads PNG headers and text chunks while leaving image data on disk.
class PngMetadataReader {
  /// Reads [file] without loading the file, or any IDAT payload, into memory.
  Future<WorldMetadata> read(File file) async {
    final fileLength = await file.length();
    final source = await file.open();
    try {
      await source.setPosition(0);
      final signature = await source.read(_pngSignature.length);
      if (signature.length != _pngSignature.length) {
        throw const PngMetadataException('The PNG signature is truncated.');
      }
      if (!_matchesSignature(signature)) {
        throw const PngMetadataException(
          'This file is not a PNG (its signature is invalid).',
        );
      }

      var position = _pngSignature.length;
      var chunkCount = 0;
      int? width;
      int? height;
      bool? isGreyscale;
      String? planetCode;
      final textChunks = <String, String>{};

      while (true) {
        if (position >= fileLength) {
          throw const PngMetadataException(
            'The PNG is truncated before its IEND chunk.',
          );
        }
        chunkCount++;
        if (chunkCount > _maxChunks) {
          throw const PngMetadataException(
            'The PNG has too many chunks to inspect safely.',
          );
        }
        if (fileLength - position < 8) {
          throw const PngMetadataException(
            'The PNG is truncated while reading a chunk header.',
          );
        }

        await source.setPosition(position);
        final header = await _readExact(
          source,
          8,
          description: 'a chunk header',
        );
        final length = _uint32(header, 0);
        final type = String.fromCharCodes(header.sublist(4, 8));
        final dataStart = position + 8;
        final remainingAfterHeader = fileLength - dataStart;
        final availablePayload = remainingAfterHeader >= 4
            ? remainingAfterHeader - 4
            : 0;
        if (remainingAfterHeader < 4 || length > availablePayload) {
          throw PngMetadataException(
            'The PNG is truncated: chunk "$type" declares $length bytes, '
            'but only $availablePayload remain.',
          );
        }
        final chunkEnd = dataStart + length + 4;

        if (type == 'IHDR') {
          if (length < 13) {
            throw const PngMetadataException(
              'The PNG IHDR chunk is truncated.',
            );
          }
          await source.setPosition(dataStart);
          final data = await _readExact(
            source,
            13,
            description: 'the IHDR chunk',
          );
          width = _uint32(data, 0);
          height = _uint32(data, 4);
          final colourType = data[9];
          // Indexed PNGs are deliberately not called greyscale: a palette
          // that happens to contain only grey colours is still indexed data.
          isGreyscale = colourType == 0 || colourType == 4;
        } else if (type == 'tEXt' || type == 'iTXt') {
          if (length > _maxTextChunkBytes) {
            throw PngMetadataException(
              'The PNG $type chunk is too large to inspect safely.',
            );
          }
          await source.setPosition(dataStart);
          final data = await _readExact(
            source,
            length,
            description: 'the $type chunk',
          );
          final entry = type == 'tEXt'
              ? _readLatin1Text(data)
              : _readInternationalText(data);
          if (entry != null) {
            textChunks[entry.keyword] = entry.text;
            if (_looksLikePlanetCode(entry.keyword)) {
              planetCode = entry.text;
            }
          }
        }

        // This also skips IDAT without reading its payload. CRCs are not
        // checked: doing so would require reading every image-data byte.
        await source.setPosition(chunkEnd);
        position = chunkEnd;
        if (type == 'IEND') break;
      }

      if (width == null || height == null || isGreyscale == null) {
        throw const PngMetadataException(
          'The PNG has no IHDR chunk describing its dimensions.',
        );
      }
      return WorldMetadata(
        width: width,
        height: height,
        isGreyscale: isGreyscale,
        planetCode: planetCode,
        textChunks: textChunks,
      );
    } finally {
      await source.close();
    }
  }
}

class _TextEntry {
  const _TextEntry(this.keyword, this.text);

  final String keyword;
  final String text;
}

Future<Uint8List> _readExact(
  RandomAccessFile source,
  int count, {
  required String description,
}) async {
  final bytes = await source.read(count);
  if (bytes.length != count) {
    throw PngMetadataException(
      'The PNG is truncated while reading $description.',
    );
  }
  return bytes;
}

_TextEntry? _readLatin1Text(Uint8List data) {
  final separator = _zeroAt(data, 0);
  if (separator < 0) return null;
  return _TextEntry(
    _latin1(data, 0, separator),
    _latin1(data, separator + 1, data.length),
  );
}

_TextEntry? _readInternationalText(Uint8List data) {
  final keywordEnd = _zeroAt(data, 0);
  if (keywordEnd < 0 || data.length < keywordEnd + 3) return null;

  final keyword = _latin1(data, 0, keywordEnd);
  final compressionFlag = data[keywordEnd + 1];
  final compressionMethod = data[keywordEnd + 2];
  if (compressionFlag == 1) {
    // Compressed iTXt is intentionally skipped. The metadata needed by this
    // feature is normally uncompressed, and inflating arbitrary text here
    // would add work and a dependency to a header-only reader.
    return null;
  }
  if (compressionFlag != 0 || compressionMethod != 0) return null;

  var cursor = keywordEnd + 3;
  final languageEnd = _zeroAt(data, cursor);
  if (languageEnd < 0) return null;
  cursor = languageEnd + 1;
  final translatedKeywordEnd = _zeroAt(data, cursor);
  if (translatedKeywordEnd < 0) return null;

  final textStart = translatedKeywordEnd + 1;
  return _TextEntry(
    keyword,
    utf8.decode(data.sublist(textStart), allowMalformed: true),
  );
}

String _latin1(Uint8List data, int start, int end) =>
    String.fromCharCodes(data.sublist(start, end));

int _zeroAt(Uint8List data, int start) {
  for (var index = start; index < data.length; index++) {
    if (data[index] == 0) return index;
  }
  return -1;
}

bool _looksLikePlanetCode(String keyword) {
  final normalized = keyword
      .toLowerCase()
      .replaceAll('_', '')
      .replaceAll('-', '')
      .replaceAll(' ', '');
  return normalized.contains('planetcode');
}

int _uint32(Uint8List data, int offset) =>
    (data[offset] << 24) |
    (data[offset + 1] << 16) |
    (data[offset + 2] << 8) |
    data[offset + 3];

bool _matchesSignature(Uint8List value) {
  for (var index = 0; index < _pngSignature.length; index++) {
    if (value[index] != _pngSignature[index]) return false;
  }
  return true;
}
