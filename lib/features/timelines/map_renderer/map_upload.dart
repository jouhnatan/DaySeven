/// Putting a map image onto a timeline.
///
/// The image is stored the way a picture in a document is — copied into the
/// Knowledge Base's `.settings/assets/` and referred to by asset id — so a map
/// travels with the folder rather than pointing at somewhere on one machine's
/// disk that the other machine has never heard of.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/domain/timeline.dart';
import 'package:dayseven/shared/kb/bundle.dart';

/// The only image types a map may be.
///
/// Narrower than the images a document accepts on purpose: a map is one large
/// picture that has to decode quickly every time the view is opened, and the
/// animated and multi-page formats have no business being one.
const List<String> kMapExtensions = ['png', 'jpg', 'jpeg'];

const XTypeGroup kMapTypeGroup = XTypeGroup(
  label: 'Map image',
  extensions: kMapExtensions,
  uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
);

/// Asks for an image and sets it as [open]'s map.
///
/// Returns null when the person cancelled, and throws [KbException] with
/// something worth reading when the file cannot be used.
Future<String?> pickAndSetTimelineMap({
  required KnowledgeBase kb,
  required OpenTimeline open,
  required TimelineController controller,
}) async {
  final file = await openFile(acceptedTypeGroups: const [kMapTypeGroup]);
  if (file == null) return null;
  return setTimelineMap(
    kb: kb,
    open: open,
    controller: controller,
    source: File(file.path),
  );
}

/// Imports [source] as [open]'s map.
///
/// Split from the picker, and given its dependencies rather than a provider
/// container, so the rule about what may be a map can be tested without a file
/// dialog.
Future<String?> setTimelineMap({
  required KnowledgeBase kb,
  required OpenTimeline open,
  required TimelineController controller,
  required File source,
}) async {
  // The picker filters, but a file can also arrive by being renamed, so the
  // rule is enforced here rather than only offered.
  final extension = source.path.toLowerCase().split('.').last;
  if (!kMapExtensions.contains(extension)) {
    throw const KbException('A map has to be a PNG or a JPEG.');
  }

  final assetId = await kb.importAsset(source);
  controller.edit(
    open.timeline.copyWith(map: TimelineMap(assetId: assetId)),
  );
  return assetId;
}

/// Takes the map off [open].
///
/// The image file itself is left where it is. Nothing else refers to it, but
/// deleting somebody's picture because they cleared a reference to it is not a
/// trade this app makes anywhere else either.
void clearTimelineMap({
  required OpenTimeline open,
  required TimelineController controller,
}) {
  if (!open.timeline.hasMap) return;
  controller.edit(open.timeline.copyWith(clearMap: true));
}
