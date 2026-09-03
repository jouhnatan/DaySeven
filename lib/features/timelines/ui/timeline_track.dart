/// The interactive horizontal axis canvas for Timeline in DaySeven.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/domain/timeline.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineTrack extends ConsumerStatefulWidget {
  const TimelineTrack({
    super.key,
    required this.timeline,
    this.trackHeight = 160,
  });

  final Timeline timeline;
  final double trackHeight;

  @override
  ConsumerState<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends ConsumerState<TimelineTrack> {
  final ScrollController _scrollController = ScrollController();

  String? _draggingItemId;
  double? _draggedStartYear;
  double? _draggedEndYear;
  double _dragOffsetDx = 0.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollLeft() {
    if (!_scrollController.hasClients) return;
    final target = math.max(0.0, _scrollController.offset - 320);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _scrollRight() {
    if (!_scrollController.hasClients) return;
    final target = math.min(
      _scrollController.position.maxScrollExtent,
      _scrollController.offset + 320,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final selectedId = ref.watch(selectedTimelineItemIdProvider);
    final items = widget.timeline.items;

    // 1. Calculate min and max year domains with padding
    final rawMin = widget.timeline.minYear;
    final rawMax = widget.timeline.maxYear;
    final span = math.max(20.0, rawMax - rawMin);
    final pad = math.max(10.0, span * 0.15);
    final minYear = (rawMin - pad).floorToDouble();
    final maxYear = (rawMax + pad).ceilToDouble();
    final totalSpan = maxYear - minYear;

    // 2. Interval ticks calculation
    final tickInterval = _computeNiceInterval(totalSpan);
    final firstTick = (minYear / tickInterval).ceil() * tickInterval;
    final ticks = <double>[];
    for (var t = firstTick; t <= maxYear; t += tickInterval) {
      ticks.add(t);
    }

    return SizedBox(
      height: widget.trackHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Caret Scroll Button (‹)
          Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: _buildCaretButton(
              context,
              icon: Icons.chevron_left,
              tooltip: 'Scroll left',
              onPressed: _scrollLeft,
            ),
          ),

          // Center Scrollable Viewport (perfectly bounded & centered)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                const edgePadding = 80.0;
                const pixelsPerYear = 8.0;
                final contentWidth = math.max(
                  availableWidth,
                  totalSpan * pixelsPerYear + (edgePadding * 2),
                );

                // Coordinate conversion helpers
                double xForYear(double year) {
                  final fraction = (year - minYear) / totalSpan;
                  return (fraction * (contentWidth - (edgePadding * 2))) +
                      edgePadding;
                }

                double yearForX(double x) {
                  final fraction =
                      (x - edgePadding) / (contentWidth - (edgePadding * 2));
                  return minYear + (fraction * totalSpan);
                }

                return ClipRect(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: contentWidth,
                      height: widget.trackHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Continuous horizontal axis line
                          Positioned(
                            left: 20,
                            right: 20,
                            top: widget.trackHeight / 2,
                            child: Container(
                              height: 2,
                              color: colors.border,
                            ),
                          ),

                          // Periodic Ticks & Year Labels
                          for (final tick in ticks) ...[
                            Positioned(
                              left: xForYear(tick) - 0.5,
                              top: (widget.trackHeight / 2) - 6,
                              child: Container(
                                width: 1,
                                height: 14,
                                color: colors.border,
                              ),
                            ),
                            Positioned(
                              left: xForYear(tick) - 30,
                              top: (widget.trackHeight / 2) + 12,
                              width: 60,
                              child: Text(
                                tick.toInt().toString(),
                                textAlign: TextAlign.center,
                                style: uiTextStyle(
                                  size: 11,
                                  color: colors.muted,
                                  tabular: true,
                                ),
                              ),
                            ),
                          ],

                          // Periods / Ages (rendered as bracketed pills)
                          for (final item in items)
                            if (item is TimelinePeriodItem)
                              _buildPeriodWidget(
                                context,
                                item,
                                xForYear,
                                yearForX,
                                isSelected: item.id == selectedId,
                              ),

                          // Point Events (rendered as nodes + blurbs)
                          for (final item in items)
                            if (item is TimelineEventItem)
                              _buildPointEventWidget(
                                context,
                                item,
                                xForYear,
                                yearForX,
                                isSelected: item.id == selectedId,
                              ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Right Caret Scroll Button (›)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 8),
            child: _buildCaretButton(
              context,
              icon: Icons.chevron_right,
              tooltip: 'Scroll right',
              onPressed: _scrollRight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaretButton(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colors = context.ds;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.island,
        elevation: 1,
        shadowColor: colors.border,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(DsRadius.control),
          side: BorderSide(color: colors.surfaceOutline),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: const BorderRadius.all(DsRadius.control),
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: colors.text,
            ),
          ),
        ),
      ),
    );
  }

  double _computeNiceInterval(double span) {
    if (span <= 50) return 10;
    if (span <= 150) return 25;
    if (span <= 300) return 50;
    if (span <= 800) return 100;
    return 250;
  }

  Widget _buildPeriodWidget(
    BuildContext context,
    TimelinePeriodItem item,
    double Function(double) xForYear,
    double Function(double) yearForX, {
    required bool isSelected,
  }) {
    final colors = context.ds;
    final itemColor = item.color.color;
    final isDragging = _draggingItemId == item.id;

    final displayStartYear =
        (isDragging && _draggedStartYear != null)
            ? _draggedStartYear!
            : widget.timeline.plotStart(item);
    final displayEndYear =
        (isDragging && _draggedEndYear != null)
            ? _draggedEndYear!
            : widget.timeline.plotEnd(item);

    final startX = xForYear(displayStartYear);
    final endX = xForYear(displayEndYear);
    final spanWidth = math.max(6.0, endX - startX);
    final centerX = (startX + endX) / 2;
    const minContainerWidth = 140.0;
    final containerWidth = math.max(minContainerWidth, spanWidth + 24.0);
    final left = centerX - (containerWidth / 2);
    final containerHeight = (widget.trackHeight / 2) + 5; // Bottom at 85px (center at 81px)

    return AnimatedPositioned(
      duration: isDragging
          ? const Duration(milliseconds: 50)
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: left,
      top: 0,
      width: containerWidth,
      height: widget.trackHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(timelineActionControllerProvider).selectItem(item.id);
        },
        onHorizontalDragStart: (details) {
          setState(() {
            _draggingItemId = item.id;
            _draggedStartYear = widget.timeline.plotStart(item);
            _draggedEndYear = widget.timeline.plotEnd(item);
            _dragOffsetDx = 0.0;
          });
          ref.read(timelineActionControllerProvider).selectItem(item.id);
        },
        onHorizontalDragUpdate: (details) {
          _dragOffsetDx += details.delta.dx;
          final currentStartX =
              xForYear(widget.timeline.plotStart(item)) + _dragOffsetDx;
          final snappedStart = yearForX(currentStartX).roundToDouble();
          final duration =
              widget.timeline.plotEnd(item) - widget.timeline.plotStart(item);
          setState(() {
            _draggedStartYear = snappedStart;
            _draggedEndYear = snappedStart + duration;
          });
        },
        onHorizontalDragEnd: (details) {
          if (_draggingItemId == item.id && _draggedStartYear != null) {
            final newStart = _draggedStartYear!.roundToDouble();
            final newEnd =
                (_draggedEndYear ??
                        (newStart +
                            (widget.timeline.plotEnd(item) -
                                widget.timeline.plotStart(item))))
                    .roundToDouble();
            ref.read(timelineActionControllerProvider).updateItem(
                  item.copyWith(
                    year: newStart.round(),
                    endYear: newEnd.round(),
                  ),
                );
          }
          setState(() {
            _draggingItemId = null;
            _draggedStartYear = null;
            _draggedEndYear = null;
            _dragOffsetDx = 0.0;
          });
        },
        child: MouseRegion(
          cursor: isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Period blurb & bracket bar
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: containerHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Blurb pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? itemColor : colors.cardSurface,
                        borderRadius: const BorderRadius.all(DsRadius.row),
                        border: Border.all(
                          color: isSelected ? itemColor : itemColor.withAlpha(160),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.hasMainDocument) ...[
                            Icon(
                              Icons.link,
                              size: 13,
                              color: isSelected ? colors.onFern : colors.link,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: uiTextStyle(
                                size: 12,
                                weight: 500,
                                color: isSelected ? colors.onFern : colors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Span bracket bar flush on the axis (accurately sized to spanWidth)
                    Container(
                      width: spanWidth,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isSelected ? itemColor : itemColor.withAlpha(200),
                        borderRadius: const BorderRadius.all(DsRadius.none),
                      ),
                    ),
                  ],
                ),
              ),

              // Live Floating Year Bubble (Appears beneath during drag)
              if (isDragging)
                Positioned(
                  left: 0,
                  right: 0,
                  top: (widget.trackHeight / 2) + 14,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: itemColor,
                        borderRadius: const BorderRadius.all(DsRadius.control),
                        border: Border.all(color: colors.surfaceOutline),
                        boxShadow: cfMenuShadow,
                      ),
                      child: Text(
                        '${displayStartYear.toInt()} → ${displayEndYear.toInt()}',
                        style: uiTextStyle(
                          size: 11,
                          weight: 600,
                          color: colors.onFern,
                          tabular: true,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPointEventWidget(
    BuildContext context,
    TimelineEventItem item,
    double Function(double) xForYear,
    double Function(double) yearForX, {
    required bool isSelected,
  }) {
    final colors = context.ds;
    final itemColor = item.color.color;
    final isDragging = _draggingItemId == item.id;

    final displayStartYear =
        (isDragging && _draggedStartYear != null)
            ? _draggedStartYear!
            : widget.timeline.plotStart(item);

    final centerX = xForYear(displayStartYear);
    final containerHeight = (widget.trackHeight / 2) + 8; // Bottom at 88px (center at 81px)

    return AnimatedPositioned(
      duration: isDragging
          ? const Duration(milliseconds: 50)
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: centerX - 60,
      top: 0,
      width: 120,
      height: widget.trackHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(timelineActionControllerProvider).selectItem(item.id);
        },
        onHorizontalDragStart: (details) {
          setState(() {
            _draggingItemId = item.id;
            _draggedStartYear = widget.timeline.plotStart(item);
            _dragOffsetDx = 0.0;
          });
          ref.read(timelineActionControllerProvider).selectItem(item.id);
        },
        onHorizontalDragUpdate: (details) {
          _dragOffsetDx += details.delta.dx;
          final currentX =
              xForYear(widget.timeline.plotStart(item)) + _dragOffsetDx;
          final snappedStart = yearForX(currentX).roundToDouble();
          setState(() {
            _draggedStartYear = snappedStart;
          });
        },
        onHorizontalDragEnd: (details) {
          if (_draggingItemId == item.id && _draggedStartYear != null) {
            final newStart = _draggedStartYear!.roundToDouble();
            ref.read(timelineActionControllerProvider).updateItem(
                  item.copyWith(
                    year: newStart.round(),
                  ),
                );
          }
          setState(() {
            _draggingItemId = null;
            _draggedStartYear = null;
            _dragOffsetDx = 0.0;
          });
        },
        child: MouseRegion(
          cursor: isDragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Point blurb and node
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: containerHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Blurb pill above the point
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? itemColor : colors.island,
                        borderRadius: const BorderRadius.all(DsRadius.row),
                        border: Border.all(
                          color: isSelected ? itemColor : itemColor.withAlpha(160),
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (item.hasMainDocument) ...[
                            Icon(
                              Icons.link,
                              size: 12,
                              color: isSelected ? colors.onFern : colors.link,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: uiTextStyle(
                                size: 11.5,
                                weight: 500,
                                color: isSelected ? colors.onFern : colors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Circular node flush on the axis line
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isSelected ? itemColor : colors.island,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: itemColor,
                          width: 2.5,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: colors.onFern,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),

              // Live Floating Year Bubble (Appears beneath during drag)
              if (isDragging)
                Positioned(
                  left: 0,
                  right: 0,
                  top: (widget.trackHeight / 2) + 14,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: itemColor,
                        borderRadius: const BorderRadius.all(DsRadius.control),
                        border: Border.all(color: colors.surfaceOutline),
                        boxShadow: cfMenuShadow,
                      ),
                      child: Text(
                        '${displayStartYear.toInt()}',
                        style: uiTextStyle(
                          size: 11,
                          weight: 600,
                          color: colors.onFern,
                          tabular: true,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
