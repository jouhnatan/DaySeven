/// State management and actions for the Timeline feature in DaySeven.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/features/timeline/domain/timeline_parser.dart';

const Uuid _uuid = Uuid();

const _parser = TimelineParser();

/// The timeline parser instance.
final timelineParserProvider = Provider<TimelineParser>((ref) => _parser);

/// The active [TimelineSection] extracted from the currently open document.
final activeTimelineSectionProvider = Provider<TimelineSection?>((ref) {
  final open = ref.watch(documentControllerProvider);
  if (open == null) return null;
  return _parser.findFirst(open.document);
});

/// The ID of the currently selected [TimelineItem] for the popover/inspector.
final selectedTimelineItemIdProvider = StateProvider<String?>((ref) => null);

/// The currently selected [TimelineItem], if any.
final selectedTimelineItemProvider = Provider<TimelineItem?>((ref) {
  final section = ref.watch(activeTimelineSectionProvider);
  final selectedId = ref.watch(selectedTimelineItemIdProvider);
  if (section == null || selectedId == null) return null;

  for (final item in section.items) {
    if (item.id == selectedId) return item;
  }
  return null;
});

/// Whether the timeline widget is collapsed into a compact header bar.
final isTimelineCollapsedProvider = StateProvider<bool>((ref) => false);

/// Controller providing mutating actions on the active document's timeline.
final timelineActionControllerProvider = Provider<TimelineActionController>((ref) {
  return TimelineActionController(ref);
});

class TimelineActionController {
  TimelineActionController(this._ref);

  final Ref _ref;

  /// Creates a new timeline section if the document does not yet have one.
  void createTimeline({String description = 'Historical Timeline'}) {
    final open = _ref.read(documentControllerProvider);
    if (open == null) return;

    final existing = _parser.findFirst(open.document);
    if (existing != null) return;

    final newSection = TimelineSection(
      startIndex: open.document.blocks.length,
      endIndex: open.document.blocks.length,
      description: description,
      items: [
        TimelinePeriodItem(
          id: _uuid.v7(),
          title: 'New age',
          startYear: 1800,
          startDateLabel: 'Year 1800',
          endYear: 1850,
          endDateLabel: 'Year 1850',
          description: 'Description of the new age...',
        ),
        TimelineEventItem(
          id: _uuid.v7(),
          title: 'New event',
          startYear: 1825,
          startDateLabel: 'Year 1825',
          description: 'Description of the event...',
        ),
      ],
    );

    final updatedDoc = _parser.insertSection(open.document, newSection);
    _ref.read(documentControllerProvider.notifier).edit(updatedDoc);
    _ref.read(isTimelineCollapsedProvider.notifier).state = false;
    _ref.read(selectedTimelineItemIdProvider.notifier).state =
        newSection.items.first.id;
  }

  /// Adds a new event or period to the active timeline.
  void addItem({required bool isPeriod}) {
    final open = _ref.read(documentControllerProvider);
    final section = _ref.read(activeTimelineSectionProvider);
    if (open == null) return;

    if (section == null) {
      createTimeline();
      return;
    }

    final double startY = section.items.isEmpty
        ? 1800
        : section.maxYear + 10;
    final String startLabel = 'Year ${startY.toInt()}';

    final TimelineItem newItem = isPeriod
        ? TimelinePeriodItem(
            id: _uuid.v7(),
            title: 'New age',
            startYear: startY,
            startDateLabel: startLabel,
            endYear: startY + 20,
            endDateLabel: 'Year ${(startY + 20).toInt()}',
            description: '',
          )
        : TimelineEventItem(
            id: _uuid.v7(),
            title: 'New event',
            startYear: startY,
            startDateLabel: startLabel,
            description: '',
          );

    final updatedSection = section.copyWith(
      items: [...section.items, newItem],
    );

    final updatedDoc = _parser.replaceSection(
      open.document,
      section,
      updatedSection,
    );
    _ref.read(documentControllerProvider.notifier).edit(updatedDoc);
    _ref.read(selectedTimelineItemIdProvider.notifier).state = newItem.id;
  }

  /// Updates an existing item in the timeline.
  void updateItem(TimelineItem updated) {
    final open = _ref.read(documentControllerProvider);
    final section = _ref.read(activeTimelineSectionProvider);
    if (open == null || section == null) return;

    final updatedItems = section.items.map((item) {
      return item.id == updated.id ? updated : item;
    }).toList();

    final updatedSection = section.copyWith(items: updatedItems);
    final updatedDoc = _parser.replaceSection(
      open.document,
      section,
      updatedSection,
    );
    _ref.read(documentControllerProvider.notifier).edit(updatedDoc);
  }

  /// Removes an item from the timeline.
  void removeItem(String itemId) {
    final open = _ref.read(documentControllerProvider);
    final section = _ref.read(activeTimelineSectionProvider);
    if (open == null || section == null) return;

    final updatedItems = section.items.where((i) => i.id != itemId).toList();
    final updatedSection = section.copyWith(items: updatedItems);
    final updatedDoc = _parser.replaceSection(
      open.document,
      section,
      updatedSection,
    );
    _ref.read(documentControllerProvider.notifier).edit(updatedDoc);

    final selectedId = _ref.read(selectedTimelineItemIdProvider);
    if (selectedId == itemId) {
      _ref.read(selectedTimelineItemIdProvider.notifier).state =
          updatedItems.isNotEmpty ? updatedItems.first.id : null;
    }
  }

  /// Updates the top-level `<timeline_desc>`.
  void updateDescription(String newDescription) {
    final open = _ref.read(documentControllerProvider);
    final section = _ref.read(activeTimelineSectionProvider);
    if (open == null || section == null) return;

    final updatedSection = section.copyWith(description: newDescription);
    final updatedDoc = _parser.replaceSection(
      open.document,
      section,
      updatedSection,
    );
    _ref.read(documentControllerProvider.notifier).edit(updatedDoc);
  }

  /// Deletes the entire timeline section from the document.
  void removeTimeline() {
    final open = _ref.read(documentControllerProvider);
    final section = _ref.read(activeTimelineSectionProvider);
    if (open == null || section == null) return;

    final updatedDoc = _parser.removeSection(open.document, section);
    _ref.read(documentControllerProvider.notifier).edit(updatedDoc);
    _ref.read(selectedTimelineItemIdProvider.notifier).state = null;
  }

  /// Selects an item on the timeline (or deselects when null).
  void selectItem(String? itemId) {
    _ref.read(selectedTimelineItemIdProvider.notifier).state = itemId;
  }
}
