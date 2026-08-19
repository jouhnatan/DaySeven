/// A Knowledge Base is a folder the user chose, treated by the app as one unit.
///
/// The user's own folders sit directly in the folder they chose — a
/// `Characters/` folder is just `Characters/`. Everything the app needs for
/// itself (the manifest, imported images, the search index) is tucked into
/// `.settings/`, where it stays out of the way. Nothing is encoded: the
/// manifest is readable JSON and `.settings/.index/` is derived and safe to
/// delete.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:dayseven/shared/blocks/blocks.dart';

const String kSettingsDirName = '.settings';
const String kManifestFileName = 'dayseven.kb.json';
const String kDocumentsDirName = 'documents';
const String kAssetsDirName = 'assets';
const String kIndexDirName = '.index';
const String kDocumentExtension = '.d7doc';
const int kBundleSchemaVersion = 1;

const _uuid = Uuid();

String newId() => _uuid.v7();

class KbManifest {
  const KbManifest({
    required this.kbId,
    required this.name,
    required this.createdAt,
    this.schemaVersion = kBundleSchemaVersion,
  });

  final String kbId;
  final String name;
  final DateTime createdAt;
  final int schemaVersion;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'kbId': kbId,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  static KbManifest fromJson(Map<String, Object?> json) => KbManifest(
    kbId: json['kbId'] as String,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    schemaVersion:
        (json['schemaVersion'] as num?)?.toInt() ?? kBundleSchemaVersion,
  );
}

/// A node in the folder-and-file tree shown in the right-hand panel.
sealed class KbNode {
  const KbNode({required this.name, required this.relativePath});

  /// Path relative to `documents/`, using forward slashes on both platforms so
  /// it matches `documents.path` in Postgres.
  final String relativePath;
  final String name;
}

class KbFolder extends KbNode {
  const KbFolder({
    required super.name,
    required super.relativePath,
    required this.children,
  });

  final List<KbNode> children;
}

class KbFile extends KbNode {
  const KbFile({
    required super.name,
    required super.relativePath,
    required this.modifiedAt,
  });

  final DateTime modifiedAt;

  /// The document title as shown in the tree: the file name without extension.
  String get displayName => p.basenameWithoutExtension(name);
}

class KnowledgeBase {
  KnowledgeBase({required this.rootPath, required this.manifest});

  /// The folder the user picked.
  final String rootPath;
  final KbManifest manifest;

  /// The app's own files. Never shown in the tree.
  String get settingsPath => p.join(rootPath, kSettingsDirName);

  /// Documents and the folders holding them live in the chosen folder itself.
  String get documentsPath => rootPath;

  String get assetsPath => p.join(settingsPath, kAssetsDirName);
  String get indexPath => p.join(settingsPath, kIndexDirName);
  String get manifestPath => p.join(settingsPath, kManifestFileName);

  /// Absolute path for a document's `documents/`-relative path.
  String absolutePathFor(String relativePath) =>
      p.join(documentsPath, p.joinAll(p.posix.split(relativePath)));

  /// The `documents/`-relative path for an absolute path, always POSIX-style.
  String relativePathFor(String absolutePath) =>
      p.posix.joinAll(p.split(p.relative(absolutePath, from: documentsPath)));

  // ------------------------------------------------------------ lifecycle --

  /// Creates a bundle in [folder], which the user chose through the system
  /// file picker. Refuses to write into a folder that already holds one.
  static Future<KnowledgeBase> create({
    required String folder,
    required String name,
    String? kbId,
  }) async {
    if (await existsIn(folder)) {
      throw const KbException('That folder already contains a Knowledge Base.');
    }

    final manifest = KbManifest(
      kbId: kbId ?? newId(),
      name: name,
      createdAt: DateTime.now().toUtc(),
    );

    final settings = p.join(folder, kSettingsDirName);
    await Directory(p.join(settings, kAssetsDirName)).create(recursive: true);
    await Directory(p.join(settings, kIndexDirName)).create(recursive: true);
    await File(p.join(settings, kManifestFileName)).writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
    );

    return KnowledgeBase(rootPath: folder, manifest: manifest);
  }

  /// Opens the bundle in [folder]. Recreates any derived directory that the
  /// user deleted, so a Knowledge Base survives being tidied up by hand.
  static Future<KnowledgeBase> open(String folder) async {
    await _migrateLayout(folder);

    final settings = p.join(folder, kSettingsDirName);
    final manifestFile = File(p.join(settings, kManifestFileName));
    if (!await manifestFile.exists()) {
      throw const KbException('No Knowledge Base in that folder.');
    }
    final manifest = KbManifest.fromJson(
      jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>,
    );

    for (final dir in [kAssetsDirName, kIndexDirName]) {
      final d = Directory(p.join(settings, dir));
      if (!await d.exists()) await d.create(recursive: true);
    }

    return KnowledgeBase(rootPath: folder, manifest: manifest);
  }

  /// True when [folder] holds a Knowledge Base, in either layout.
  static Future<bool> existsIn(String folder) async =>
      await File(p.join(folder, kSettingsDirName, kManifestFileName))
          .exists() ||
      await File(p.join(folder, kManifestFileName)).exists();

  /// Brings an older Knowledge Base up to the current layout, in place.
  ///
  /// Two earlier shapes exist: everything at the top of the folder, and
  /// everything under `.settings/`. Either way the app's own files end up in
  /// `.settings/` and the user's documents end up in the folder itself.
  /// Entries are renamed rather than copied, so files keep their identity.
  static Future<void> _migrateLayout(String folder) async {
    final settings = Directory(p.join(folder, kSettingsDirName));
    final rootManifest = File(p.join(folder, kManifestFileName));
    final rootDocuments = Directory(p.join(folder, kDocumentsDirName));
    final nestedDocuments = Directory(p.join(settings.path, kDocumentsDirName));

    final fromFlat = await rootManifest.exists();
    final fromNested = await nestedDocuments.exists();
    if (!fromFlat && !fromNested) return;

    await settings.create(recursive: true);

    if (fromFlat) {
      for (final name in [kAssetsDirName, kIndexDirName]) {
        final from = Directory(p.join(folder, name));
        final to = p.join(settings.path, name);
        if (await from.exists() && !await Directory(to).exists()) {
          await from.rename(to);
        }
      }

      final target = p.join(settings.path, kManifestFileName);
      if (await File(target).exists()) {
        await rootManifest.delete();
      } else {
        await rootManifest.rename(target);
      }
    }

    // Documents move up into the folder itself, from wherever they were.
    for (final source in [nestedDocuments, rootDocuments]) {
      if (!await source.exists()) continue;

      await for (final entity in source.list(followLinks: false)) {
        final target = p.join(folder, p.basename(entity.path));
        if (await FileSystemEntity.type(target) !=
            FileSystemEntityType.notFound) {
          continue; // Something is already there; leave both alone.
        }
        await entity.rename(target);
      }

      // Non-recursive: an emptied folder goes, anything left behind stays.
      try {
        await source.delete();
      } on FileSystemException {
        // Still holds something that could not be moved; that is the user's.
      }
    }
  }

  // ------------------------------------------------------------------ tree --

  Future<List<KbNode>> readTree() => _readFolder(documentsPath, '');

  Future<List<KbNode>> _readFolder(String absolute, String relative) async {
    final dir = Directory(absolute);
    if (!await dir.exists()) return const [];

    final folders = <KbFolder>[];
    final files = <KbFile>[];

    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final childRelative = relative.isEmpty ? name : '$relative/$name';

      if (entity is Directory) {
        folders.add(
          KbFolder(
            name: name,
            relativePath: childRelative,
            children: await _readFolder(entity.path, childRelative),
          ),
        );
      } else if (entity is File && name.endsWith(kDocumentExtension)) {
        files.add(
          KbFile(
            name: name,
            relativePath: childRelative,
            modifiedAt: (await entity.stat()).modified,
          ),
        );
      }
    }

    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...folders, ...files];
  }

  // ------------------------------------------------------------- documents --

  Future<BlockDocument> readDocument(String relativePath) async {
    final file = File(absolutePathFor(relativePath));
    return BlockDocument.decode(await file.readAsString());
  }

  /// Writes through a temporary file and renames, so an interrupted save can
  /// never leave a half-written document on the user's disk.
  Future<void> writeDocument(
    String relativePath,
    BlockDocument document,
  ) async {
    final target = File(absolutePathFor(relativePath));
    await target.parent.create(recursive: true);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(document.encode(), flush: true);
    await temp.rename(target.path);
  }

  /// Creates an empty document with one paragraph, ready to type into.
  Future<String> createDocument({
    required String title,
    String folderRelativePath = '',
  }) async {
    final fileName = '${_sanitizeFileName(title)}$kDocumentExtension';
    final relativePath = folderRelativePath.isEmpty
        ? fileName
        : '$folderRelativePath/$fileName';

    if (await File(absolutePathFor(relativePath)).exists()) {
      throw KbException('A document called "$title" is already there.');
    }

    await writeDocument(
      relativePath,
      BlockDocument(
        id: newId(),
        title: title,
        blocks: [ParagraphBlock(id: newId(), spans: const [])],
      ),
    );
    return relativePath;
  }

  Future<void> createFolder(String relativePath) =>
      Directory(absolutePathFor(relativePath)).create(recursive: true);

  /// Moves a document or folder into [targetFolderRelativePath] (empty for the
  /// top level) and returns its new path.
  ///
  /// The entry is renamed, not copied, so a document keeps its identity on disk
  /// and its `.d7doc` contents — including the document id the revisions in
  /// Postgres are keyed by — are untouched.
  Future<String> move(
    String relativePath,
    String targetFolderRelativePath,
  ) async {
    final name = p.posix.basename(relativePath);
    final currentFolder = p.posix.dirname(relativePath);
    final target = targetFolderRelativePath.isEmpty
        ? '.'
        : targetFolderRelativePath;

    if (currentFolder == target) return relativePath;

    // A folder cannot be moved inside itself, directly or further down.
    if (target == relativePath || p.posix.isWithin(relativePath, target)) {
      throw const KbException('A folder cannot be moved inside itself.');
    }

    final destination = target == '.'
        ? name
        : p.posix.join(targetFolderRelativePath, name);

    if (await FileSystemEntity.type(absolutePathFor(destination)) !=
        FileSystemEntityType.notFound) {
      throw KbException('"$name" is already there.');
    }

    final from = absolutePathFor(relativePath);
    final type = await FileSystemEntity.type(from);
    switch (type) {
      case FileSystemEntityType.directory:
        await Directory(from).rename(absolutePathFor(destination));
      case FileSystemEntityType.file:
        await File(from).rename(absolutePathFor(destination));
      default:
        throw const KbException('That item is no longer there.');
    }

    return destination;
  }

  Future<void> deleteDocument(String relativePath) async {
    final file = File(absolutePathFor(relativePath));
    if (await file.exists()) await file.delete();
  }

  // ---------------------------------------------------------------- assets --

  String assetPathFor(String assetId) => p.join(assetsPath, assetId);

  Future<String> importAsset(File source) async {
    final assetId = '${newId()}${p.extension(source.path)}';
    await Directory(assetsPath).create(recursive: true);
    await source.copy(p.join(assetsPath, assetId));
    return assetId;
  }
}

/// Strips characters that are illegal in a file name on either platform.
String _sanitizeFileName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final trimmed = cleaned.replaceAll(RegExp(r'\.+$'), '');
  return trimmed.isEmpty ? 'Untitled' : trimmed;
}

class KbException implements Exception {
  const KbException(this.message);
  final String message;

  @override
  String toString() => message;
}
