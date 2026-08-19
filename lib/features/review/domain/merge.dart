/// Three-way merge over the block document model.
///
/// Approving a proposal merges three documents: the `base` the proposal was
/// written against, the reviewer's current `local` revision, and the `proposed`
/// content. Blocks are aligned by their stable ids, so a paragraph that merely
/// moved is recognised as the same paragraph. Within a paragraph the merge runs
/// at character level, and formatting travels with the characters it applies
/// to — that is what lets one side re-word a sentence while the other bolds a
/// different phrase, and keep both.
///
/// Where the two sides genuinely overlap, the proposal wins and the block is
/// reported as conflicted so the reviewer sees it marked in the diff before
/// approving. Pure Dart.
library;

import 'package:diff_match_patch/diff_match_patch.dart' as dmp;

import 'package:dayseven/shared/blocks/blocks.dart';

class MergeResult {
  const MergeResult({required this.document, required this.conflictedBlockIds});

  final BlockDocument document;

  /// Blocks where both sides changed the same region. The proposal's version
  /// was taken; the diff view marks these before Approve is pressed.
  final List<String> conflictedBlockIds;

  bool get hasConflicts => conflictedBlockIds.isNotEmpty;
}

/// Merges [proposed] into [local], both derived from [base].
MergeResult threeWayMerge({
  required BlockDocument base,
  required BlockDocument local,
  required BlockDocument proposed,
}) {
  final baseById = {for (final b in base.blocks) b.id: b};
  final localById = {for (final b in local.blocks) b.id: b};
  final proposedById = {for (final b in proposed.blocks) b.id: b};

  final order = _mergeOrder(
    baseIds: base.blocks.map((b) => b.id).toList(),
    localIds: local.blocks.map((b) => b.id).toList(),
    proposedIds: proposed.blocks.map((b) => b.id).toList(),
  );

  final conflicts = <String>[];
  final blocks = <Block>[];

  for (final id in order) {
    final b = baseById[id];
    final l = localById[id];
    final p = proposedById[id];

    if (b == null) {
      // Added by one side, or by both. If both added a block under the same id
      // with different content, treat it as a content conflict.
      if (l != null && p != null) {
        final merged = _mergeBlock(base: l, local: l, proposed: p);
        blocks.add(merged.block);
        if (merged.conflicted) conflicts.add(id);
      } else {
        blocks.add((p ?? l)!);
      }
      continue;
    }

    // Deleted by one side: honour the deletion.
    if (l == null || p == null) continue;

    final merged = _mergeBlock(base: b, local: l, proposed: p);
    blocks.add(merged.block);
    if (merged.conflicted) conflicts.add(id);
  }

  final title = local.title == base.title ? proposed.title : local.title;

  return MergeResult(
    document: BlockDocument(
      id: local.id,
      title: title,
      blocks: blocks,
      schemaVersion: local.schemaVersion,
    ),
    conflictedBlockIds: conflicts,
  );
}

// ---------------------------------------------------------------- ordering --

/// Merges three id sequences: base order is the spine, ids removed by either
/// side drop out, and ids added by a side are re-inserted after whatever
/// preceded them on that side.
List<String> _mergeOrder({
  required List<String> baseIds,
  required List<String> localIds,
  required List<String> proposedIds,
}) {
  final baseSet = baseIds.toSet();
  final localSet = localIds.toSet();
  final proposedSet = proposedIds.toSet();

  // Survivors keep the order of whichever side reordered them; when both
  // reordered, the proposal's order wins for that region.
  final survivors = <String>[];
  final proposedOrderOfSurvivors = proposedIds.where(
    (id) => !baseSet.contains(id) || localSet.contains(id),
  );
  final localOrderOfSurvivors = localIds.where(
    (id) => !baseSet.contains(id) || proposedSet.contains(id),
  );

  final localReordered = !_sameOrder(
    localIds.where(baseSet.contains).toList(),
    baseIds.where(localSet.contains).toList(),
  );
  final proposedReordered = !_sameOrder(
    proposedIds.where(baseSet.contains).toList(),
    baseIds.where(proposedSet.contains).toList(),
  );

  final spine = proposedReordered || !localReordered
      ? proposedOrderOfSurvivors
      : localOrderOfSurvivors;

  final seen = <String>{};
  for (final id in spine) {
    if (seen.add(id)) survivors.add(id);
  }

  // Anything the other side added that the spine does not carry: insert after
  // its predecessor on the side that added it.
  final fromOther = spine == proposedOrderOfSurvivors ? localIds : proposedIds;
  for (var i = 0; i < fromOther.length; i++) {
    final id = fromOther[i];
    if (seen.contains(id)) continue;
    if (baseSet.contains(id)) continue; // deleted by the other side
    final predecessor = i == 0 ? null : fromOther[i - 1];
    final at = predecessor == null ? 0 : survivors.indexOf(predecessor) + 1;
    survivors.insert(at.clamp(0, survivors.length), id);
    seen.add(id);
  }

  return survivors;
}

bool _sameOrder(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// ------------------------------------------------------------------ blocks --

class _MergedBlock {
  const _MergedBlock(this.block, this.conflicted);
  final Block block;
  final bool conflicted;
}

_MergedBlock _mergeBlock({
  required Block base,
  required Block local,
  required Block proposed,
}) {
  final align = _pick(base.align, local.align, proposed.align);
  final spaceBefore = _pick(
    base.spaceBefore,
    local.spaceBefore,
    proposed.spaceBefore,
  );

  // Paragraphs and headings merge identically — the text merge only wants
  // spans. Note these are `is` tests, not a switch: a block type added without
  // a branch here would fall through to "the proposal wins" and silently
  // discard the local side, so anything with spans must be caught by TextBlock.
  if (base is TextBlock && local is TextBlock && proposed is TextBlock) {
    // A paragraph turned into a heading on one side is a change of kind, not
    // of text; fall through and let the proposal win.
    if (base.runtimeType == local.runtimeType &&
        base.runtimeType == proposed.runtimeType) {
      final text = _mergeSpans(base, local, proposed);
      var merged = local
          .withSpans(text.spans)
          .copyWithCommon(align: align, spaceBefore: spaceBefore);

      if (base is HeadingBlock &&
          local is HeadingBlock &&
          proposed is HeadingBlock) {
        merged = (merged as HeadingBlock).copyWith(
          level: _pick(base.level, local.level, proposed.level),
        );
      }

      return _MergedBlock(merged, text.conflicted);
    }
  }

  if (base is ImageBlock && local is ImageBlock && proposed is ImageBlock) {
    return _MergedBlock(
      ImageBlock(
        id: local.id,
        assetId: _pick(base.assetId, local.assetId, proposed.assetId),
        caption: _pick(base.caption, local.caption, proposed.caption),
        align: align,
        spaceBefore: spaceBefore,
      ),
      false,
    );
  }

  // The block changed type on at least one side; the proposal wins.
  return _MergedBlock(proposed, true);
}

/// Standard three-way pick for a scalar attribute.
T _pick<T>(T base, T local, T proposed) {
  if (local == base) return proposed;
  if (proposed == base) return local;
  return proposed;
}

// ------------------------------------------------- character-level merging --

class _MergedSpans {
  const _MergedSpans(this.spans, this.conflicted);
  final List<TextSpanNode> spans;
  final bool conflicted;
}

/// One character plus the formatting that applies to it.
class _StyledChar {
  const _StyledChar(this.char, this.format);
  final String char;
  final TextSpanNode format;

  bool sameFormat(_StyledChar other) => format.sameFormatting(other.format);
}

List<_StyledChar> _explode(TextBlock block) {
  final out = <_StyledChar>[];
  for (final span in block.spans) {
    for (final ch in span.text.split('')) {
      out.add(_StyledChar(ch, span));
    }
  }
  return out;
}

List<TextSpanNode> _implode(List<_StyledChar> chars) {
  final spans = <TextSpanNode>[];
  final buffer = StringBuffer();
  TextSpanNode? current;

  void flush() {
    if (current != null && buffer.isNotEmpty) {
      spans.add(current.copyWith(text: buffer.toString()));
    }
    buffer.clear();
  }

  for (final c in chars) {
    if (current == null || !current.sameFormatting(c.format)) {
      flush();
      current = c.format;
    }
    buffer.write(c.char);
  }
  flush();
  return spans;
}

/// One contiguous edit of the base, expressed as: at base index [at], drop
/// [deleteLength] characters and insert [insert].
class _Edit {
  _Edit(this.at);
  final int at;
  int deleteLength = 0;
  final List<_StyledChar> insert = [];

  bool sameAs(_Edit other) {
    if (deleteLength != other.deleteLength) return false;
    if (insert.length != other.insert.length) return false;
    for (var i = 0; i < insert.length; i++) {
      if (insert[i].char != other.insert[i].char) return false;
      if (!insert[i].sameFormat(other.insert[i])) return false;
    }
    return true;
  }
}

/// A side's changes relative to the base: its edits, and where each surviving
/// base character ended up on that side (so its formatting can be compared).
class _Script {
  _Script(int baseLength) : survivorIndex = List.filled(baseLength, null);
  final List<_Edit> edits = [];
  final List<int?> survivorIndex;

  _Edit? editAt(int baseIndex) {
    for (final e in edits) {
      if (e.at == baseIndex) return e;
    }
    return null;
  }

  bool touchesRange(int start, int end) =>
      edits.any((e) => e.at >= start && e.at < end);
}

_Script _scriptFor(List<_StyledChar> base, List<_StyledChar> side) {
  final baseText = base.map((c) => c.char).join();
  final sideText = side.map((c) => c.char).join();
  final diffs = dmp.diff(baseText, sideText);
  dmp.cleanupSemantic(diffs);

  final script = _Script(base.length);
  var bi = 0;
  var si = 0;
  _Edit? pending;

  for (final d in diffs) {
    switch (d.operation) {
      case dmp.DIFF_EQUAL:
        pending = null;
        for (var k = 0; k < d.text.length; k++) {
          script.survivorIndex[bi] = si;
          bi++;
          si++;
        }
      case dmp.DIFF_DELETE:
        if (pending == null) {
          pending = _Edit(bi);
          script.edits.add(pending);
        }
        pending.deleteLength += d.text.length;
        bi += d.text.length;
      case dmp.DIFF_INSERT:
        if (pending == null) {
          pending = _Edit(bi);
          script.edits.add(pending);
        }
        for (var k = 0; k < d.text.length; k++) {
          pending.insert.add(side[si]);
          si++;
        }
    }
  }
  return script;
}

_MergedSpans _mergeSpans(TextBlock base, TextBlock local, TextBlock proposed) {
  final baseChars = _explode(base);
  final localChars = _explode(local);
  final proposedChars = _explode(proposed);

  bool identicalChars(List<_StyledChar> a, List<_StyledChar> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].char != b[i].char || !a[i].sameFormat(b[i])) return false;
    }
    return true;
  }

  // Fast paths: one side did not touch this paragraph, or both made the same
  // change. No diffing needed, and no chance of a conflict.
  if (identicalChars(baseChars, localChars)) {
    return _MergedSpans(proposed.normalized().spans, false);
  }
  if (identicalChars(baseChars, proposedChars)) {
    return _MergedSpans(local.normalized().spans, false);
  }
  if (identicalChars(localChars, proposedChars)) {
    return _MergedSpans(local.normalized().spans, false);
  }

  final localScript = _scriptFor(baseChars, localChars);
  final proposedScript = _scriptFor(baseChars, proposedChars);

  final out = <_StyledChar>[];
  var conflicted = false;
  var bi = 0;

  while (bi <= baseChars.length) {
    final le = localScript.editAt(bi);
    final pe = proposedScript.editAt(bi);

    if (le != null || pe != null) {
      if (le != null && pe != null) {
        if (le.sameAs(pe)) {
          out.addAll(pe.insert);
          bi += pe.deleteLength;
        } else {
          // Both sides edited the same spot differently: the proposal wins.
          conflicted = true;
          out.addAll(pe.insert);
          bi += pe.deleteLength;
        }
      } else {
        final edit = le ?? pe!;
        final otherScript = le != null ? proposedScript : localScript;
        // A deletion on one side that swallows an edit on the other is an
        // overlap, even though the two edits start at different indices.
        if (edit.deleteLength > 0 &&
            otherScript.touchesRange(
              edit.at + 1,
              edit.at + edit.deleteLength,
            )) {
          conflicted = true;
        }
        out.addAll(edit.insert);
        bi += edit.deleteLength;
      }
      continue;
    }

    if (bi == baseChars.length) break;

    // This base character survived on both sides. Resolve its formatting.
    final li = localScript.survivorIndex[bi];
    final pi = proposedScript.survivorIndex[bi];
    final bc = baseChars[bi];
    final lc = li == null ? null : localChars[li];
    final pc = pi == null ? null : proposedChars[pi];

    if (lc == null && pc == null) {
      // Consumed by an edit on both sides; nothing to emit.
    } else if (lc == null) {
      out.add(pc!);
    } else if (pc == null) {
      out.add(lc);
    } else if (lc.sameFormat(bc)) {
      out.add(pc);
    } else if (pc.sameFormat(bc)) {
      out.add(lc);
    } else if (lc.sameFormat(pc)) {
      out.add(lc);
    } else {
      conflicted = true;
      out.add(pc);
    }
    bi++;
  }

  return _MergedSpans(_implode(out), conflicted);
}
