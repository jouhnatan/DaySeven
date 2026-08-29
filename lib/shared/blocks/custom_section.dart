/// Generic abstraction for encapsulated custom block sections in DaySeven documents.
///
/// Pure Dart — nothing in this file may import Flutter or Supabase.
library;

import 'package:dayseven/shared/blocks/blocks.dart';

/// Base class for any structured section extracted from a [BlockDocument].
abstract class CustomSection {
  const CustomSection({required this.startIndex, required this.endIndex});

  /// Index of the opening boundary block in [BlockDocument.blocks].
  final int startIndex;

  /// Index of the closing boundary block in [BlockDocument.blocks].
  final int endIndex;

  /// Number of blocks consumed by this section in the parent document.
  int get blockCount => endIndex - startIndex + 1;
}

/// Generic parser interface for extracting custom objects from [BlockDocument].
abstract class CustomSectionParser<T extends CustomSection> {
  const CustomSectionParser({required this.sectionHeader});

  /// The heading title that bounds this section (e.g. `Timeline`).
  final String sectionHeader;

  /// Finds the first matching section in [document], or null if none exists.
  T? findFirst(BlockDocument document);

  /// Finds all matching sections in [document].
  List<T> parseAll(BlockDocument document);

  /// Serializes [section] into a list of [Block]s that can replace the range.
  List<Block> serializeSection(T section);

  /// Replaces [oldSection] with [newSection] in [document] and returns the updated document.
  BlockDocument replaceSection(
    BlockDocument document,
    T oldSection,
    T newSection,
  ) {
    final blocks = [...document.blocks];
    final serialized = serializeSection(newSection);
    blocks.replaceRange(oldSection.startIndex, oldSection.endIndex + 1, serialized);
    return document.copyWith(blocks: blocks);
  }

  /// Inserts a new [section] at [insertIndex] (or end of document if omitted).
  BlockDocument insertSection(BlockDocument document, T section, {int? insertIndex}) {
    final blocks = [...document.blocks];
    final at = insertIndex ?? blocks.length;
    final serialized = serializeSection(section);
    blocks.insertAll(at, serialized);
    return document.copyWith(blocks: blocks);
  }

  /// Removes [section] from [document].
  BlockDocument removeSection(BlockDocument document, T section) {
    final blocks = [...document.blocks];
    blocks.removeRange(section.startIndex, section.endIndex + 1);
    return document.copyWith(blocks: blocks);
  }
}
