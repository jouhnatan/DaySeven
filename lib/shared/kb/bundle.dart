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
import 'package:dayseven/shared/blocks/markdown.dart';

const String kSettingsDirName = '.settings';
const String kMetadataDirName = 'metadata';
const String kManifestFileName = 'dayseven.kb.json';
const String kDocumentsDirName = 'documents';
const String kAssetsDirName = 'assets';
const String kIndexDirName = '.index';
const String kDocumentExtension = '.md';

/// The JSON format documents used to be written in. Still read, and still
/// written back to, so a document that could not be converted is not silently
/// dropped from the tree — see [KnowledgeBase._migrateDocumentFormat].
const String kLegacyDocumentExtension = '.d7doc';

/// What a converted document's original is renamed to. Never deleted.
const String kConvertedBackupSuffix = '.bak';

const int kBundleSchemaVersion = 2;

/// True for a file this app treats as a document, in either format.
bool isDocumentPath(String path) =>
    path.endsWith(kDocumentExtension) ||
    path.endsWith(kLegacyDocumentExtension);

/// The user-facing title of a document is its file name without the document
/// extension. The relative path is always POSIX-style, even on Windows.
String documentTitleFromPath(String relativePath) =>
    p.posix.basenameWithoutExtension(relativePath);

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
  const KbFile({required super.name, required super.relativePath});

  /// The document title as shown in the tree: the file name without extension.
  String get displayName => p.basenameWithoutExtension(name);
}

/// Depth-first traversal shared by indexing, syncing, and workspace state.
Iterable<KbNode> walkKbTree(Iterable<KbNode> nodes) sync* {
  for (final node in nodes) {
    yield node;
    if (node is KbFolder) yield* walkKbTree(node.children);
  }
}

Iterable<String> documentPathsIn(Iterable<KbNode> nodes) =>
    walkKbTree(nodes).whereType<KbFile>().map((file) => file.relativePath);

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

    await _migrateDocumentFormat(folder);

    var current = manifest;
    if (manifest.schemaVersion < kBundleSchemaVersion) {
      current = KbManifest(
        kbId: manifest.kbId,
        name: manifest.name,
        createdAt: manifest.createdAt,
      );
      await manifestFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(current.toJson()),
      );
    }

    return KnowledgeBase(rootPath: folder, manifest: current);
  }

  /// Rewrites any remaining JSON document as Markdown, in place.
  ///
  /// Runs on every open rather than once behind a version check. It is one
  /// directory walk — the same cost as the `readTree` that follows moments
  /// later — and running always makes it self-healing: a `.d7doc` restored from
  /// a backup or synced in from another machine is picked up rather than
  /// sitting unconverted forever.
  ///
  /// Nothing is ever deleted and nothing is overwritten. A document that
  /// cannot be converted keeps its original file and stays fully readable and
  /// writable, because [isDocumentPath] still recognises it.
  static Future<void> _migrateDocumentFormat(String folder) async {
    final root = Directory(folder);
    if (!await root.exists()) return;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith(kLegacyDocumentExtension)) continue;

      // `.settings/`, `metadata/` and anything else hidden is the app's, not the user's.
      final relative = p.relative(entity.path, from: folder);
      final segments = p.split(relative);
      if (segments.any((part) => part.startsWith('.')) ||
          (segments.isNotEmpty && segments.first == kMetadataDirName)) {
        continue;
      }

      try {
        await _convertOneDocument(entity);
      } on Object {
        // One unconvertible document must not stop the rest, and leaving it
        // as it was is always the safe outcome.
        continue;
      }
    }
  }

  static Future<void> _convertOneDocument(File source) async {
    final stem = source.path.substring(
      0,
      source.path.length - kLegacyDocumentExtension.length,
    );
    final target = File('$stem$kDocumentExtension');
    final document = BlockDocument.decode(await source.readAsString());

    if (await target.exists()) {
      // Either a previous run was interrupted after writing but before
      // renaming, in which case finish it; or the user has two documents with
      // the same name, in which case touch neither.
      final existing = decodeMarkdown(await target.readAsString());
      if (existing.sameContentAs(document)) {
        await source.rename('${source.path}$kConvertedBackupSuffix');
      }
      return;
    }

    final markdown = encodeMarkdown(document);

    // The gate that makes this safe: if the document does not survive its own
    // round trip, write nothing at all. No serializer bug can destroy content.
    if (!decodeMarkdown(markdown).sameContentAs(document)) return;

    final temp = File('${target.path}.tmp');
    await temp.writeAsString(markdown, flush: true);
    await temp.rename(target.path);
    await source.rename('${source.path}$kConvertedBackupSuffix');
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

  /// The folders and documents a person should see.
  ///
  /// `metadata/` holds `workspace.bin` and the signed policy — the workspace's
  /// own bookkeeping rather than anybody's writing — so it is hidden the way
  /// `.settings/` is. [includeMetadata] is the developer setting that reveals
  /// it, for when somebody debugging sync needs to see that those files exist.
  /// It changes only what is listed: deleting inside `metadata/` stays refused
  /// regardless, and `workspace.bin` is never openable as a document.
  Future<List<KbNode>> readTree({bool includeMetadata = false}) =>
      _readFolder(documentsPath, '', includeMetadata: includeMetadata);

  Future<List<KbNode>> _readFolder(
    String absolute,
    String relative, {
    required bool includeMetadata,
  }) async {
    final dir = Directory(absolute);
    if (!await dir.exists()) return const [];

    final folders = <KbFolder>[];
    final files = <KbFile>[];

    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (relative.isEmpty && name == kMetadataDirName && !includeMetadata) {
        continue;
      }
      final childRelative = relative.isEmpty ? name : '$relative/$name';

      if (entity is Directory) {
        folders.add(
          KbFolder(
            name: name,
            relativePath: childRelative,
            children: await _readFolder(
              entity.path,
              childRelative,
              includeMetadata: includeMetadata,
            ),
          ),
        );
      } else if (entity is File && isDocumentPath(name)) {
        files.add(KbFile(name: name, relativePath: childRelative));
      }
    }

    folders.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [...folders, ...files];
  }

  // ------------------------------------------------------------- documents --

  /// Reads a document in whichever format it is stored in, so a file that
  /// failed conversion still opens.
  Future<BlockDocument> readDocument(String relativePath) async {
    final file = File(absolutePathFor(relativePath));
    final source = await file.readAsString();
    return relativePath.endsWith(kLegacyDocumentExtension)
        ? BlockDocument.decode(source)
        : decodeMarkdown(source);
  }

  /// Writes through a temporary file and renames, so an interrupted save can
  /// never leave a half-written document on the user's disk.
  Future<void> writeDocument(
    String relativePath,
    BlockDocument document,
  ) async {
    final target = File(absolutePathFor(relativePath));
    await target.parent.create(recursive: true);
    final source = relativePath.endsWith(kLegacyDocumentExtension)
        ? document.encode()
        : encodeMarkdown(document);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(source, flush: true);
    await temp.rename(target.path);
  }

  /// Creates an empty document with one paragraph, ready to type into.
  Future<String> createDocument({
    required String title,
    String folderRelativePath = '',
  }) async {
    final fileName = '${sanitizeNodeName(title)}$kDocumentExtension';
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

  /// Renames one document within its current folder and keeps the title stored
  /// in the document in step with the Markdown file name.
  Future<String> renameDocument(
    String relativePath,
    String requestedName,
  ) async {
    if (!isDocumentPath(relativePath)) {
      throw const KbException('Only documents can be renamed here.');
    }

    var name = requestedName.trim();
    for (final extension in [kDocumentExtension, kLegacyDocumentExtension]) {
      if (name.toLowerCase().endsWith(extension)) {
        name = name.substring(0, name.length - extension.length);
        break;
      }
    }

    final title = sanitizeNodeName(name);
    final extension = relativePath.endsWith(kLegacyDocumentExtension)
        ? kLegacyDocumentExtension
        : kDocumentExtension;
    final folder = p.posix.dirname(relativePath);
    final fileName = '$title$extension';
    final destination = folder == '.'
        ? fileName
        : p.posix.join(folder, fileName);
    final from = absolutePathFor(relativePath);

    if (await FileSystemEntity.type(from) != FileSystemEntityType.file) {
      throw const KbException('That document is no longer there.');
    }

    // Do not let the two supported document formats shadow one another with
    // the same visible name. Case-only renames are allowed when both paths
    // identify the source file on a case-insensitive filesystem.
    for (final candidateExtension in [
      kDocumentExtension,
      kLegacyDocumentExtension,
    ]) {
      final candidateName = '$title$candidateExtension';
      final candidate = folder == '.'
          ? candidateName
          : p.posix.join(folder, candidateName);
      final candidatePath = absolutePathFor(candidate);
      if (await FileSystemEntity.type(candidatePath) ==
          FileSystemEntityType.notFound) {
        continue;
      }

      var isSource = candidate == relativePath;
      if (!isSource) {
        try {
          isSource = await FileSystemEntity.identical(from, candidatePath);
        } on FileSystemException {
          isSource = false;
        }
      }
      if (!isSource) {
        throw KbException('A document called "$title" is already there.');
      }
    }

    if (destination != relativePath) {
      await File(from).rename(absolutePathFor(destination));
    }

    final document = await readDocument(destination);
    if (document.title != title) {
      await writeDocument(destination, document.copyWith(title: title));
    }
    return destination;
  }

  /// Moves a document or folder into [targetFolderRelativePath] (empty for the
  /// top level) and returns its new path.
  ///
  /// The entry is renamed, not copied, so a document keeps its identity on disk
  /// and its contents — including the document id the revisions in Postgres are
  /// keyed by — are untouched.
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

  /// Permanently deletes one visible file or folder from the Knowledge Base.
  ///
  /// This method accepts only the canonical, POSIX-style relative paths that
  /// [readTree] returns. The checks are intentionally repeated here, at the
  /// filesystem boundary, because deleting a directory is recursive.
  Future<void> deleteNode(String relativePath) async {
    final normalized = p.posix.normalize(relativePath);
    final segments = p.posix.split(relativePath);
    final isUnsafe =
        relativePath.isEmpty ||
        normalized == '.' ||
        normalized != relativePath ||
        p.posix.isAbsolute(relativePath) ||
        p.windows.isAbsolute(relativePath) ||
        segments.isEmpty ||
        segments.any((part) => part == '.' || part == '..') ||
        segments.first == kSettingsDirName ||
        segments.first == kMetadataDirName;
    if (isUnsafe) {
      throw const KbException('That item cannot be deleted.');
    }

    final target = absolutePathFor(relativePath);
    if (!p.isWithin(documentsPath, target)) {
      throw const KbException('That item cannot be deleted.');
    }

    switch (await FileSystemEntity.type(target, followLinks: false)) {
      case FileSystemEntityType.file:
        await File(target).delete();
      case FileSystemEntityType.directory:
        await Directory(target).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(target).delete();
      case FileSystemEntityType.notFound:
        throw const KbException('That item is no longer there.');
      default:
        throw const KbException('That item cannot be deleted.');
    }
  }

  // ---------------------------------------------------------------- assets --

  String assetPathFor(String assetId) => p.join(assetsPath, assetId);

  Future<String> importAsset(File source) async {
    final length = await source.length();
    if (length > kMaxImageBytes) {
      throw const KbException(
        'That image is too large (max 10 MB). Choose a smaller file.',
      );
    }
    if (length == 0) {
      throw const KbException('That image file is empty.');
    }
    final allowed = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.tiff', '.tif'};
    final ext = p.extension(source.path).toLowerCase();
    if (ext.isNotEmpty && !allowed.contains(ext)) {
      throw KbException('Unsupported image type "$ext".');
    }
    final assetId = '${newId()}${p.extension(source.path)}';
    await Directory(assetsPath).create(recursive: true);
    await source.copy(p.join(assetsPath, assetId));
    return assetId;
  }
}

/// Strips characters that are illegal in a file name on either platform.
String sanitizeNodeName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final trimmed = cleaned.replaceAll(RegExp(r'\.+$'), '');
  if (trimmed.isEmpty) return 'Untitled';

  // Windows reserves these device names even when an extension follows them.
  final firstSegment = trimmed.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(firstSegment)) {
    return '_$trimmed';
  }
  return trimmed;
}

class KbException implements Exception {
  const KbException(this.message);
  final String message;

  @override
  String toString() => message;
}
