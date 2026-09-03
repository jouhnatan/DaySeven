/// What may be a map, and where it ends up.
library;

import 'dart:io';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/map_renderer/map_upload.dart';
import 'package:dayseven/features/timelines/map_renderer/map_viewport.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/kb_harness.dart';

// Plain tests rather than `testWidgets`: nothing here builds a widget, and the
// whole point is real disk I/O — which under `testWidgets`' fake clock has no
// time in which to finish.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() async {
    final dirs = await createTempDirs('dayseven_map_test');
    temp = dirs.temp;
  });

  /// A Knowledge Base with one timeline open, ready to be given a map.
  Future<(ProviderContainer, KnowledgeBase)> openTimeline() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(kbControllerProvider.notifier)
        .openFolder(temp.path, createWithName: 'MyWorld');
    final kb = container.read(kbSessionProvider)!.kb;

    final path = await kb.createObject(
      name: 'Third Age',
      seed: newTimelineSeed(),
    );
    await container.read(openTimelineProvider.notifier).open(path);
    return (container, kb);
  }

  Future<File> imageNamed(String name) async {
    final file = File(p.join(temp.parent.path, name));
    // A real PNG header, so nothing downstream is fooled by an empty file.
    await file.writeAsBytes(<int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13,
    ]);
    addTearDown(() async {
      if (await file.exists()) await file.delete();
    });
    return file;
  }

  Future<String?> setMap(
    ProviderContainer container,
    KnowledgeBase kb,
    File source,
  ) => setTimelineMap(
    kb: kb,
    open: container.read(openTimelineProvider)!,
    controller: container.read(openTimelineProvider.notifier),
    source: source,
  );

  test('a PNG becomes the timeline map', () async {
    final (container, kb) = await openTimeline();

    final assetId = await setMap(
      container,
      kb,
      await imageNamed('world.png'),
    );

    expect(assetId, isNotNull);
    expect(assetId, endsWith('.png'));
    // Copied into the Knowledge Base, so the map travels with the folder
    // rather than pointing at one machine's disk.
    expect(File(kb.assetPathFor(assetId!)).existsSync(), isTrue);
    expect(container.read(openTimelineProvider)!.timeline.map!.assetId, assetId);
  });

  test('a JPEG is a map too', () async {
    final (container, kb) = await openTimeline();
    for (final name in ['world.jpg', 'world.jpeg', 'WORLD.JPEG']) {
      expect(
        await setMap(container, kb, await imageNamed(name)),
        isNotNull,
        reason: '$name should be accepted',
      );
    }
  });

  test('anything else is refused, whatever the picker allowed', () async {
    final (container, kb) = await openTimeline();

    // A GIF is an image the editor accepts in a document, and still not a map.
    for (final name in ['world.gif', 'world.webp', 'notes.txt']) {
      await expectLater(
        setMap(container, kb, await imageNamed(name)),
        throwsA(isA<KbException>()),
        reason: '$name should be refused',
      );
    }
    expect(container.read(openTimelineProvider)!.timeline.hasMap, isFalse);
  });

  test('clearing the map leaves the image on disk', () async {
    final (container, kb) = await openTimeline();
    final assetId = await setMap(
      container,
      kb,
      await imageNamed('world.png'),
    );

    clearTimelineMap(
      open: container.read(openTimelineProvider)!,
      controller: container.read(openTimelineProvider.notifier),
    );

    expect(container.read(openTimelineProvider)!.timeline.hasMap, isFalse);
    expect(
      File(kb.assetPathFor(assetId!)).existsSync(),
      isTrue,
      reason: 'clearing a reference is not a reason to delete somebody\'s file',
    );
  });

  test('the map survives a save and reopen', () async {
    final (container, kb) = await openTimeline();
    final assetId = await setMap(
      container,
      kb,
      await imageNamed('world.png'),
    );

    await container.read(openTimelineProvider.notifier).flush();
    await container
        .read(openTimelineProvider.notifier)
        .open('Third Age.unearth');

    expect(container.read(openTimelineProvider)!.timeline.map!.assetId, assetId);
  });

  group('viewport', () {
    const size = Size(800, 600);

    test('starts showing the whole map, and cannot zoom out past it', () {
      final viewport = MapViewportController();
      addTearDown(viewport.dispose);

      expect(viewport.scale, kMapMinScale);
      expect(viewport.canZoomOut, isFalse);
      expect(viewport.canZoomIn, isTrue);
    });

    test('zooming in and back out returns to the whole map', () {
      final viewport = MapViewportController();
      addTearDown(viewport.dispose);

      viewport.zoomIn(size);
      expect(viewport.scale, greaterThan(kMapMinScale));
      expect(viewport.canZoomOut, isTrue);

      viewport.zoomOut(size);
      expect(viewport.scale, closeTo(kMapMinScale, 0.0001));
    });

    test('stops at the closest it goes', () {
      final viewport = MapViewportController();
      addTearDown(viewport.dispose);

      for (var i = 0; i < 20; i++) {
        viewport.zoomIn(size);
      }
      expect(viewport.scale, closeTo(kMapMaxScale, 0.0001));
      expect(viewport.canZoomIn, isFalse);
    });

    test('reset returns to the whole map from anywhere', () {
      final viewport = MapViewportController();
      addTearDown(viewport.dispose);

      viewport
        ..zoomIn(size)
        ..zoomIn(size)
        ..reset();
      expect(viewport.scale, kMapMinScale);
    });

    test('a screen point maps back onto the image it was clicked on', () {
      final viewport = MapViewportController();
      addTearDown(viewport.dispose);

      // Unzoomed, the two coordinate spaces are the same.
      expect(viewport.toImagePoint(const Offset(100, 50)), const Offset(100, 50));

      // Zoomed about the centre, the centre of the pane is still the same
      // point on the map — which is what pin placement will rely on.
      viewport.zoomIn(size);
      final centre = Offset(size.width / 2, size.height / 2);
      final mapped = viewport.toImagePoint(centre);
      expect(mapped.dx, closeTo(centre.dx, 0.001));
      expect(mapped.dy, closeTo(centre.dy, 0.001));
    });
  });
}
