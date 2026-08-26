/// Turning collaborators' Awareness anchors into carets in this copy.
///
/// A peer sends where their caret is as a Yjs relative position — an anchor
/// naming the character it sits beside by CRDT identity, not an index. This
/// resolves those anchors against the local document.
///
/// Two things make that more than a decode:
///
///   * The anchor may name text this copy has deleted. `yrs` then resolves to
///     where the text used to be rather than failing, which is the right
///     behaviour for drawing a caret but makes the answer a hint. Everything
///     here clamps against the local length before returning.
///   * The anchor may be for a file this copy does not share, or be malformed
///     because it came from a build that encodes something else. Both resolve
///     to null rather than throwing: a cursor that cannot be placed is not
///     drawn, and presence has never been allowed to fail loudly.
library;

import 'dart:convert';

import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/presence/peer_presence.dart';

/// Where to draw one collaborator's caret in the local copy of a file.
class ResolvedCaret {
  const ResolvedCaret({
    required this.userId,
    required this.offset,
    this.selectionOffset,
  });

  final String userId;

  /// UTF-16 offset into the local text, already clamped to be valid.
  final int offset;

  /// The other end of their selection, when they have one. Never equal to
  /// [offset] — a zero-width selection is a caret.
  final int? selectionOffset;

  bool get hasSelection => selectionOffset != null;

  /// Ordered so a caller can draw a range without re-comparing.
  int get start =>
      selectionOffset == null || selectionOffset! > offset ? offset : selectionOffset!;
  int get end =>
      selectionOffset == null || selectionOffset! < offset ? offset : selectionOffset!;
}

class AwarenessResolver {
  const AwarenessResolver(this.store);

  final WorkspaceStore store;

  /// Encodes this device's caret so collaborators can place it.
  ///
  /// Returns null when the file is not in the workspace, or when the offset is
  /// not a position in it — an editor and a CRDT document can disagree for a
  /// moment after an external edit, and a wrong cursor is worse than none.
  Future<String?> encodeCaret({
    required String fileId,
    required int offset,
  }) async {
    if (offset < 0) return null;
    try {
      final position = await store.relativePosition(
        fileId: fileId,
        index: offset,
      );
      return position.isEmpty ? null : base64Encode(position);
    } on Object {
      return null;
    }
  }

  /// Resolves one peer's anchors into a caret in the local copy.
  ///
  /// Null when they are not in this file, have sent no cursor, or their anchor
  /// cannot be placed here.
  Future<ResolvedCaret?> resolve(
    PeerPresence peer, {
    required String fileId,
  }) async {
    if (peer.documentId != fileId) return null;
    final cursor = peer.cursor;
    if (cursor == null) return null;

    final length = await _length(fileId);
    if (length == null) return null;

    final offset = await _resolveOne(cursor, fileId: fileId, length: length);
    if (offset == null) return null;

    final anchor = peer.selectionAnchor;
    final selection = anchor == null
        ? null
        : await _resolveOne(anchor, fileId: fileId, length: length);

    return ResolvedCaret(
      userId: peer.userId,
      offset: offset,
      // A selection that collapsed to the caret is a caret.
      selectionOffset: selection == offset ? null : selection,
    );
  }

  /// Every peer who can be placed in this file, in the order given.
  Future<List<ResolvedCaret>> resolveAll(
    Iterable<PeerPresence> peers, {
    required String fileId,
  }) async {
    final carets = <ResolvedCaret>[];
    for (final peer in peers) {
      final caret = await resolve(peer, fileId: fileId);
      if (caret != null) carets.add(caret);
    }
    return carets;
  }

  Future<int?> _resolveOne(
    String encoded, {
    required String fileId,
    required int length,
  }) async {
    final List<int> bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      return null;
    }
    try {
      final index = await store.absoluteIndex(fileId: fileId, position: bytes);
      if (index == null) return null;
      // The clamp the Rust side asks for: a resolved index is a hint, and an
      // anchor in deleted text can name a position past the end of what is
      // left.
      return index < 0 ? 0 : (index > length ? length : index);
    } on Object {
      return null;
    }
  }

  Future<int?> _length(String fileId) async {
    try {
      return (await store.getFileText(fileId)).length;
    } on Object {
      return null;
    }
  }
}
