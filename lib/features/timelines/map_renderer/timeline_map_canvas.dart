/// The centre of the Timelines view: the map.
///
/// Without one, the surface asks for one. With one, it is the map and the
/// controls for moving around it — and nothing else ever takes this slot.
///
/// When pin placement arrives, it belongs here: a control that arms placing,
/// a tap turned into image coordinates by [MapViewportController.toImagePoint],
/// and a marker layer inside the transformed child so a pin stays on the
/// place it marks as the map is panned and zoomed. `TimelineItem` grows
/// `double? pinX, pinY` at that point and the schema steps again — deliberately
/// not carried now, so it is not a field nothing writes.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/map_renderer/map_upload.dart';
import 'package:dayseven/features/timelines/map_renderer/map_viewport.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineMapCanvas extends ConsumerStatefulWidget {
  const TimelineMapCanvas({super.key});

  @override
  ConsumerState<TimelineMapCanvas> createState() => _TimelineMapCanvasState();
}

class _TimelineMapCanvasState extends ConsumerState<TimelineMapCanvas> {
  final MapViewportController _viewport = MapViewportController();
  String? _failure;
  bool _busy = false;

  @override
  void dispose() {
    _viewport.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final session = ref.read(kbSessionProvider);
    final open = ref.read(openTimelineProvider);
    if (_busy || session == null || open == null) return;

    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await pickAndSetTimelineMap(
        kb: session.kb,
        open: open,
        controller: ref.read(openTimelineProvider.notifier),
      );
      _viewport.reset();
    } on KbException catch (error) {
      if (mounted) setState(() => _failure = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _clear() {
    final open = ref.read(openTimelineProvider);
    if (open == null) return;
    clearTimelineMap(
      open: open,
      controller: ref.read(openTimelineProvider.notifier),
    );
    _viewport.reset();
    setState(() => _failure = null);
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openTimelineProvider);
    final session = ref.watch(kbSessionProvider);
    final map = open?.timeline.map;

    return DsPane(
      key: const Key('timeline-map-canvas'),
      editorSurface: true,
      child: map == null || session == null
          ? _MapEmptyState(
              // Uploading needs somewhere to put the map, so it needs a
              // timeline open to put it on.
              onUpload: open == null || _busy ? null : _upload,
              busy: _busy,
              failure: _failure,
            )
          : _MapSurface(
              key: ValueKey(map.assetId),
              file: File(session.kb.assetPathFor(map.assetId)),
              viewport: _viewport,
              onReplace: _busy ? null : _upload,
              onClear: _clear,
              failure: _failure,
            ),
    );
  }
}

class _MapEmptyState extends StatelessWidget {
  const _MapEmptyState({
    required this.onUpload,
    required this.busy,
    required this.failure,
  });

  final VoidCallback? onUpload;
  final bool busy;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'No map yet.',
              textAlign: TextAlign.center,
              style: uiTextStyle(size: 13, color: colors.faint),
            ),
            const SizedBox(height: DsSpace.gap),
            DsButton(
              key: const Key('timeline-map-upload'),
              variant: DsButtonVariant.secondary,
              height: DsSize.control,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.m),
              onPressed: onUpload,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: onUpload == null ? colors.faint : colors.text,
                  ),
                  const SizedBox(width: DsSpace.s),
                  // The centre can be narrow when both side panes are open, so
                  // the label gives way rather than overflowing the pane.
                  Flexible(
                    child: Text(
                      busy ? 'Adding…' : 'Upload a map',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: uiTextStyle(
                        size: 13,
                        weight: 500,
                        color: onUpload == null ? colors.faint : colors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: DsSpace.s),
            Text(
              onUpload == null && !busy
                  ? 'Open a timeline first.'
                  : 'PNG or JPEG.',
              textAlign: TextAlign.center,
              style: uiTextStyle(size: 12, color: colors.faint),
            ),
            if (failure != null) ...[
              const SizedBox(height: DsSpace.gap),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DsErrorBox(failure!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The map, and the controls for moving around it.
class _MapSurface extends StatelessWidget {
  const _MapSurface({
    super.key,
    required this.file,
    required this.viewport,
    required this.onReplace,
    required this.onClear,
    required this.failure,
  });

  final File file;
  final MapViewportController viewport;
  final VoidCallback? onReplace;
  final VoidCallback onClear;
  final String? failure;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: InteractiveViewer(
                  key: const Key('timeline-map-viewer'),
                  transformationController: viewport.transform,
                  minScale: kMapMinScale,
                  maxScale: kMapMaxScale,
                  // The map does not drift away from its own pane: panning
                  // stops where the image does.
                  constrained: true,
                  clipBehavior: Clip.none,
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                    errorBuilder: (context, _, _) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DsSpace.l),
                        child: DsErrorBox(
                          'That map image is missing from this Knowledge Base.',
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: DsSpace.gap,
              bottom: DsSpace.gap,
              child: _MapControls(
                viewport: viewport,
                size: size,
                onReplace: onReplace,
                onClear: onClear,
              ),
            ),
            if (failure != null)
              Positioned(
                left: DsSpace.gap,
                right: DsSpace.gap,
                bottom: DsSpace.gap,
                child: DsErrorBox(failure!),
              ),
          ],
        );
      },
    );
  }
}

class _MapControls extends StatelessWidget {
  const _MapControls({
    required this.viewport,
    required this.size,
    required this.onReplace,
    required this.onClear,
  });

  final MapViewportController viewport;
  final Size size;
  final VoidCallback? onReplace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return AnimatedBuilder(
      animation: viewport,
      builder: (context, _) {
        Widget button({
          required Key key,
          required IconData icon,
          required String tooltip,
          required VoidCallback? onPressed,
        }) => Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: DsSize.smallControl,
            child: DsButton(
              key: key,
              height: DsSize.smallControl,
              padding: EdgeInsets.zero,
              onPressed: onPressed,
              child: Icon(
                icon,
                size: 16,
                color: onPressed == null ? colors.faint : colors.text,
              ),
            ),
          ),
        );

        return Container(
          padding: const EdgeInsets.all(DsSpace.xs),
          decoration: BoxDecoration(
            color: colors.island,
            borderRadius: const BorderRadius.all(DsRadius.menu),
            border: Border.all(color: colors.surfaceOutline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(
                key: const Key('timeline-map-zoom-out'),
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: viewport.canZoomOut
                    ? () => viewport.zoomOut(size)
                    : null,
              ),
              const SizedBox(width: DsSpace.xxs),
              button(
                key: const Key('timeline-map-zoom-in'),
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: viewport.canZoomIn
                    ? () => viewport.zoomIn(size)
                    : null,
              ),
              const SizedBox(width: DsSpace.xxs),
              button(
                key: const Key('timeline-map-reset'),
                icon: Icons.fit_screen_outlined,
                tooltip: 'Fit the whole map',
                onPressed: viewport.canZoomOut ? viewport.reset : null,
              ),
              const SizedBox(width: DsSpace.s),
              button(
                key: const Key('timeline-map-replace'),
                icon: Icons.image_outlined,
                tooltip: 'Replace this map',
                onPressed: onReplace == null
                    ? null
                    : () => unawaited(Future<void>.sync(onReplace!)),
              ),
              const SizedBox(width: DsSpace.xxs),
              button(
                key: const Key('timeline-map-clear'),
                icon: Icons.close,
                tooltip: 'Remove this map',
                onPressed: onClear,
              ),
            ],
          ),
        );
      },
    );
  }
}
