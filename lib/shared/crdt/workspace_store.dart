/// Manages the CRDT workspace for a Knowledge Base.
///
/// Handles on-disk loading and validation of `metadata/yjs/workspace.bin`,
/// recursive scanning and importing of Markdown documents, atomic debounced
/// persistence, materialisation of Y.Text to Markdown, external edit ingestion,
/// and strict path traversal and symlink validation.
///
/// Sits in `shared/crdt/` and depends only on `shared/` models and the Rust CRDT core.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/markdown.dart';
import 'package:dayseven/shared/crdt/generated/api/workspace.dart';
import 'package:dayseven/shared/kb/bundle.dart';

const String kYjsSubdirName = 'yjs';
const String kWorkspaceBinName = 'workspace.bin';
const String kWorkspaceTmpName = 'workspace.bin.tmp';

/// 50 MB default size limit for a single workspace document.
const int kDefaultMaxWorkspaceBytes = 50 * 1024 * 1024;

/// Matches the 600 ms debounce in open_document.dart.
const Duration kDefaultSaveDebounce = Duration(milliseconds: 600);

class WorkspaceStoreException implements Exception {
  const WorkspaceStoreException(this.message);
  final String message;

  @override
  String toString() => message;
}

class WorkspaceSizeExceededException extends WorkspaceStoreException {
  const WorkspaceSizeExceededException(super.message);
}

class PathSecurityException extends WorkspaceStoreException {
  const PathSecurityException(super.message);
}

class WorkspaceStore {
  WorkspaceStore._({
    required this.rootPath,
    required this.workspaceId,
    required this.handle,
    this.maxWorkspaceBytes = kDefaultMaxWorkspaceBytes,
    this.debounceDuration = kDefaultSaveDebounce,
  });

  final String rootPath;
  final String workspaceId;
  final int maxWorkspaceBytes;
  final Duration debounceDuration;
  final BigInt handle;

  bool _isDirty = false;
  bool _isClosed = false;
  bool get isClosed => _isClosed;
  bool get isDirty => _isDirty;

  Timer? _debounceTimer;
  final Map<String, DateTime> _recentlyMaterialized = {};

  String get metadataYjsPath => p.join(rootPath, kMetadataDirName, kYjsSubdirName);
  String get workspaceBinPath => p.join(metadataYjsPath, kWorkspaceBinName);
  String get workspaceTmpPath => p.join(metadataYjsPath, kWorkspaceTmpName);

  /// Opens or restores a WorkspaceStore for [rootPath].
  ///
  /// 1. Creates `<kb-root>/metadata/yjs/` if missing.
  /// 2. Loads `workspace.bin` if present, validating schema version.
  /// 3. Recursively scans for `.md` files (ignoring `metadata/` and `.settings/`).
  /// 4. Matches known files by normalized path; imports Markdown into `Y.Text`.
  static Future<WorkspaceStore> open({
    required String rootPath,
    required String workspaceId,
    int maxWorkspaceBytes = kDefaultMaxWorkspaceBytes,
    Duration debounceDuration = kDefaultSaveDebounce,
  }) async {
    final metadataDir = Directory(p.join(rootPath, kMetadataDirName, kYjsSubdirName));
    if (!await metadataDir.exists()) {
      await metadataDir.create(recursive: true);
    }

    final binFile = File(p.join(metadataDir.path, kWorkspaceBinName));
    final wasRestoredFromBin = await binFile.exists();
    BigInt handle;
    if (wasRestoredFromBin) {
      final bytes = await binFile.readAsBytes();
      try {
        handle = await workspaceLoad(bytes: bytes);
      } catch (e) {
        throw WorkspaceStoreException('Failed to load workspace: $e');
      }
    } else {
      try {
        handle = await workspaceCreate(workspaceId: workspaceId);
      } catch (e) {
        throw WorkspaceStoreException('Failed to create workspace: $e');
      }
    }

    final store = WorkspaceStore._(
      rootPath: rootPath,
      workspaceId: workspaceId,
      handle: handle,
      maxWorkspaceBytes: maxWorkspaceBytes,
      debounceDuration: debounceDuration,
    );

    try {
      await store._scanAndImport(wasRestoredFromBin: wasRestoredFromBin);
    } catch (e) {
      await store.close();
      rethrow;
    }

    return store;
  }

  /// Convenience factory opening a store for an existing [KnowledgeBase].
  static Future<WorkspaceStore> openFor(
    KnowledgeBase kb, {
    int maxWorkspaceBytes = kDefaultMaxWorkspaceBytes,
    Duration debounceDuration = kDefaultSaveDebounce,
  }) =>
      open(
        rootPath: kb.rootPath,
        workspaceId: kb.manifest.kbId,
        maxWorkspaceBytes: maxWorkspaceBytes,
        debounceDuration: debounceDuration,
      );

  // -------------------------------------------------------- Path Security --

  /// Validates that [relativePath] is a safe Markdown target within [rootPath].
  ///
  /// Rejects path traversal (`..`), symlinks escaping the root, non-Markdown targets,
  /// and target paths outside [rootPath].
  void validateDocumentPath(String relativePath) {
    validatePathSafety(rootPath, relativePath);
  }

  /// Static path security checker usable across the CRDT subsystem.
  static void validatePathSafety(String rootPath, String relativePath) {
    final normalized = p.posix.normalize(relativePath);
    final segments = p.posix.split(relativePath);

    if (relativePath.isEmpty ||
        normalized == '.' ||
        normalized.startsWith('../') ||
        normalized == '..' ||
        p.posix.isAbsolute(relativePath) ||
        p.windows.isAbsolute(relativePath) ||
        segments.isEmpty ||
        segments.any((part) => part == '..' || part == '.') ||
        segments.first == kSettingsDirName ||
        segments.first == kMetadataDirName ||
        !relativePath.toLowerCase().endsWith(kDocumentExtension)) {
      throw PathSecurityException('Invalid or forbidden document path: "$relativePath"');
    }

    final targetAbsolute = p.join(rootPath, p.joinAll(p.posix.split(relativePath)));
    if (!p.isWithin(rootPath, targetAbsolute)) {
      throw PathSecurityException('Path escapes workspace root: "$relativePath"');
    }

    String canonicalRoot;
    try {
      canonicalRoot = Directory(rootPath).resolveSymbolicLinksSync();
    } catch (_) {
      canonicalRoot = rootPath;
    }

    bool isWithinRoot(String path) =>
        p.isWithin(rootPath, path) ||
        path == rootPath ||
        p.isWithin(canonicalRoot, path) ||
        path == canonicalRoot;

    // Verify symlink escapes on target or any parent directory
    final targetEntity = File(targetAbsolute);
    if (targetEntity.existsSync()) {
      try {
        final resolved = targetEntity.resolveSymbolicLinksSync();
        if (!isWithinRoot(resolved)) {
          throw PathSecurityException('Symlink escapes workspace root: "$relativePath" -> "$resolved"');
        }
      } on FileSystemException {
        // Target path does not exist as a link or cannot be resolved.
      }
    } else {
      var current = targetEntity.parent;
      while (current.path != rootPath && p.isWithin(rootPath, current.path)) {
        if (current.existsSync()) {
          try {
            final resolved = current.resolveSymbolicLinksSync();
            if (!isWithinRoot(resolved)) {
              throw PathSecurityException('Parent directory symlink escapes workspace root: "$relativePath"');
            }
          } on FileSystemException {
            // Parent directory cannot be resolved as link.
          }
        }
        current = current.parent;
      }
    }
  }

  // ---------------------------------------------------- Scan and Initial Import --

  Future<void> _scanAndImport({required bool wasRestoredFromBin}) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;

    final existingIds = await fileIds(handle: handle);
    final knownByPath = <String, FileMeta>{};
    final knownById = <String, FileMeta>{};
    for (final id in existingIds) {
      try {
        final meta = await fileMeta(handle: handle, fileId: id);
        knownById[id] = meta;
        knownByPath[meta.path] = meta;
      } catch (_) {
        // File may have been removed concurrently.
      }
    }

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!isDocumentPath(entity.path)) continue;

      final relative = p.posix.joinAll(p.split(p.relative(entity.path, from: rootPath)));
      final segments = p.posix.split(relative);
      if (segments.any((part) => part.startsWith('.')) ||
          (segments.isNotEmpty && segments.first == kMetadataDirName)) {
        continue;
      }

      try {
        validateDocumentPath(relative);
      } catch (_) {
        continue;
      }

      final content = await entity.readAsString();
      BlockDocument doc;
      try {
        doc = decodeMarkdown(content);
      } catch (_) {
        continue;
      }

      String fileId = doc.id;
      final matchedByPath = knownByPath[relative];
      if (matchedByPath != null) {
        fileId = matchedByPath.fileId;
      }

      if (knownById.containsKey(fileId)) {
        final meta = knownById[fileId]!;
        if (meta.path != relative) {
          await fileUpsert(
            handle: handle,
            fileId: fileId,
            path: relative,
            protected: meta.protected,
            owners: meta.owners,
          );
        }
        if (!wasRestoredFromBin) {
          final currentText = await fileText(handle: handle, fileId: fileId);
          if (currentText != content) {
            await fileSetText(handle: handle, fileId: fileId, next: content);
            _markDirty();
          }
        } else {
          final binFile = File(workspaceBinPath);
          if (binFile.existsSync()) {
            final binModified = binFile.statSync().modified;
            final fileModified = entity.statSync().modified;
            if (fileModified.isAfter(binModified)) {
              final currentText = await fileText(handle: handle, fileId: fileId);
              if (currentText != content) {
                await fileSetText(handle: handle, fileId: fileId, next: content);
                _markDirty();
              }
            }
          }
        }
      } else {
        await fileUpsert(
          handle: handle,
          fileId: fileId,
          path: relative,
          protected: false,
          owners: const [],
        );
        await fileSetText(handle: handle, fileId: fileId, next: content);
        final meta = FileMeta(
          fileId: fileId,
          path: relative,
          protected: false,
          owners: const [],
        );
        knownById[fileId] = meta;
        knownByPath[relative] = meta;
        _markDirty();
      }
    }
  }

  // ------------------------------------------------------------ Persistence --

  void _markDirty() {
    if (_isClosed) return;
    _isDirty = true;
    _scheduleSave();
  }

  void _scheduleSave() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDuration, () {
      unawaited(flush());
    });
  }

  /// Flushes current CRDT state to `workspace.bin` atomically via a temporary file.
  Future<void> flush() async {
    if (_isClosed) return;
    _debounceTimer?.cancel();

    final bytes = await workspaceEncode(handle: handle);
    if (bytes.length > maxWorkspaceBytes) {
      throw WorkspaceSizeExceededException(
        'Workspace size (${bytes.length} bytes) exceeds configured maximum ($maxWorkspaceBytes bytes)',
      );
    }

    final metadataDir = Directory(metadataYjsPath);
    if (!await metadataDir.exists()) {
      await metadataDir.create(recursive: true);
    }

    final target = File(workspaceBinPath);
    final temp = File(workspaceTmpPath);

    await temp.writeAsBytes(bytes, flush: true);
    await temp.rename(target.path);
    _isDirty = false;
  }

  // --------------------------------------------------- Markdown Materialisation --

  /// Writes the Y.Text content for [fileId] to disk via atomic temp-file rename.
  Future<void> materializeFile(String fileId) async {
    _checkNotClosed();
    final meta = await fileMeta(handle: handle, fileId: fileId);
    validateDocumentPath(meta.path);

    final text = await fileText(handle: handle, fileId: fileId);
    final targetAbsolute = p.join(rootPath, p.joinAll(p.posix.split(meta.path)));
    final targetFile = File(targetAbsolute);

    await targetFile.parent.create(recursive: true);

    if (await targetFile.exists()) {
      final diskContent = await targetFile.readAsString();
      if (diskContent == text) return;
    }

    // Suppress watcher reflection
    _recentlyMaterialized[meta.path] = DateTime.now();

    final tempFile = File('$targetAbsolute.tmp');
    await tempFile.writeAsString(text, flush: true);
    await tempFile.rename(targetAbsolute);
  }

  /// Materializes all files in the CRDT workspace to disk.
  Future<void> materializeAll() async {
    _checkNotClosed();
    final ids = await fileIds(handle: handle);
    for (final id in ids) {
      await materializeFile(id);
    }
  }

  /// Returns true if a filesystem watcher event for [relativePath] was caused
  /// by a recent store materialisation write and should be suppressed.
  bool shouldSuppressWatcher(
    String relativePath, {
    Duration window = const Duration(milliseconds: 1000),
  }) {
    final timestamp = _recentlyMaterialized.remove(relativePath);
    if (timestamp == null) return false;
    final elapsed = DateTime.now().difference(timestamp);
    return elapsed < window;
  }

  // -------------------------------------------------------- External Edits --

  /// Ingests an external file edit on disk into `Y.Text` via `fileSetText`.
  Future<void> applyExternalEdit(String relativePath) async {
    _checkNotClosed();
    validateDocumentPath(relativePath);

    final targetAbsolute = p.join(rootPath, p.joinAll(p.posix.split(relativePath)));
    final targetFile = File(targetAbsolute);
    if (!await targetFile.exists()) return;

    final content = await targetFile.readAsString();

    final ids = await fileIds(handle: handle);
    String? matchedId;
    for (final id in ids) {
      final meta = await fileMeta(handle: handle, fileId: id);
      if (meta.path == relativePath) {
        matchedId = id;
        break;
      }
    }

    if (matchedId == null) {
      final doc = decodeMarkdown(content);
      matchedId = doc.id;
      await fileUpsert(
        handle: handle,
        fileId: matchedId,
        path: relativePath,
        protected: false,
        owners: const [],
      );
    }

    final current = await fileText(handle: handle, fileId: matchedId);
    if (current != content) {
      await fileSetText(handle: handle, fileId: matchedId, next: content);
      _markDirty();
    }
  }

  /// Ingests a file rename made externally or through KnowledgeBase tree actions.
  Future<void> handleFileRenamed({
    required String oldPath,
    required String newPath,
  }) async {
    _checkNotClosed();
    validateDocumentPath(newPath);

    final ids = await fileIds(handle: handle);
    for (final id in ids) {
      final meta = await fileMeta(handle: handle, fileId: id);
      if (meta.path == oldPath) {
        await fileUpsert(
          handle: handle,
          fileId: id,
          path: newPath,
          protected: meta.protected,
          owners: meta.owners,
        );
        _markDirty();
        break;
      }
    }
  }

  /// Removes a file from the CRDT workspace following a deletion on disk.
  Future<void> handleFileDeleted(String relativePath) async {
    _checkNotClosed();
    final ids = await fileIds(handle: handle);
    for (final id in ids) {
      final meta = await fileMeta(handle: handle, fileId: id);
      if (meta.path == relativePath) {
        await fileRemove(handle: handle, fileId: id);
        _markDirty();
        break;
      }
    }
  }

  // ------------------------------------------------------- CRDT Operations --

  Future<List<String>> getFileIds() async {
    _checkNotClosed();
    return fileIds(handle: handle);
  }

  Future<FileMeta> getFileMeta(String fileId) async {
    _checkNotClosed();
    return fileMeta(handle: handle, fileId: fileId);
  }

  Future<String> getFileText(String fileId) async {
    _checkNotClosed();
    return fileText(handle: handle, fileId: fileId);
  }

  Future<void> upsertFile({
    required String fileId,
    required String path,
    bool protected = false,
    List<String> owners = const [],
  }) async {
    _checkNotClosed();
    validateDocumentPath(path);
    await fileUpsert(
      handle: handle,
      fileId: fileId,
      path: path,
      protected: protected,
      owners: owners,
    );
    _markDirty();
  }

  Future<void> setFileText({
    required String fileId,
    required String next,
  }) async {
    _checkNotClosed();
    final current = await fileText(handle: handle, fileId: fileId);
    if (current != next) {
      await fileSetText(handle: handle, fileId: fileId, next: next);
      _markDirty();
    }
  }

  Future<void> removeFile(String fileId) async {
    _checkNotClosed();
    await fileRemove(handle: handle, fileId: fileId);
    _markDirty();
  }

  Future<Uint8List> encode() async {
    _checkNotClosed();
    return workspaceEncode(handle: handle);
  }

  Future<Uint8List> stateVector() async {
    _checkNotClosed();
    return workspaceStateVector(handle: handle);
  }

  Future<Uint8List> diff(List<int> sinceStateVector) async {
    _checkNotClosed();
    return workspaceDiff(handle: handle, sinceStateVector: sinceStateVector);
  }

  Future<List<String>> applyUpdate(List<int> update) async {
    _checkNotClosed();
    final touched = await workspaceApply(handle: handle, update: update);
    if (touched.isNotEmpty) {
      _markDirty();
    }
    return touched;
  }

  Future<List<String>> stageApplyUpdate(List<int> update) async {
    _checkNotClosed();
    return workspaceStageApply(handle: handle, update: update);
  }

  // ------------------------------------------------------------- Lifecycle --

  void _checkNotClosed() {
    if (_isClosed) {
      throw const WorkspaceStoreException('WorkspaceStore is closed.');
    }
  }

  /// Closes the store, flushes any pending dirty changes, and releases the Rust handle.
  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _debounceTimer?.cancel();
    if (_isDirty) {
      try {
        await flush();
      } catch (_) {
        // Suppress flush error on close
      }
    }
    await workspaceClose(handle: handle);
  }
}
