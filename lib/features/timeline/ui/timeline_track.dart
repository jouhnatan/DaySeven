/// The interactive horizontal axis canvas for Timeline in DaySeven.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineTrack extends ConsumerStatefulWidget {
  const TimelineTrack({
    super.key,
    required this.section,
    this.trackHeight = 160,
  });

  final TimelineSection section;
  final double trackHeight;

  @override
  ConsumerState<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends ConsumerState<TimelineTrack> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final selectedId = ref.watch(selectedTimelineItemIdProvider);
    final items = widget.section.items;

    // 1. Calculate min and max year domains with padding
    final rawMin = widget.section.minYear;
    final rawMax = widget.section.maxYear;
    final span = math.max(20.0, rawMax - rawMin);
    final pad = math.max(10.0, span * 0.15);
    final minYear = (rawMin - pad).floorToDouble();
    final maxYear = (rawMax + pad).ceilToDouble();
    final totalSpan = maxYear - minYear;

    // 2. Pixel density: at least 1000px total width
    const minTrackWidth = 900.0;
    const pixelsPerYear = 6.0;
    final trackWidth = math.max(minTrackWidth, totalSpan * pixelsPerYear);

    // 3. Coordinate conversion helper
    double xForYear(double year) {
      final fraction = (year - minYear) / totalSpan;
      return (fraction * (trackWidth - 120)) + 60;
    }

    // 4. Generate interval ticks
    final tickInterval = _computeNiceInterval(totalSpan);
    final firstTick = (minYear / tickInterval).ceil() * tickInterval;
    final ticks = <double>[];
    for (var t = firstTick; t <= maxYear; t += tickInterval) {
      ticks.add(t);
    }

    return SizedBox(
      height: widget.trackHeight,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: trackWidth,
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
                    isSelected: item.id == selectedId,
                  ),

              // Point Events (rendered as nodes + blurbs)
              for (final item in items)
                if (item is TimelineEventItem)
                  _buildPointEventWidget(
                    context,
                    item,
                    xForYear,
                    isSelected: item.id == selectedId,
                  ),
            ],
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
    double Function(double) xForYear, {
    required bool isSelected,
  }) {
    final colors = context.ds;
    final itemColor = item.color.color;
    final startX = xForYear(item.startYear);
    final endX = xForYear(item.endYear);
    final width = math.max(70.0, endX - startX);
    final left = startX;
    final containerHeight = (widget.trackHeight / 2) + 5; // Bottom at 85px (center at 81px)

    return Positioned(
      left: left,
      top: 0,
      width: width,
      height: containerHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(timelineActionControllerProvider).selectItem(item.id);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
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
                    if (item.isDocumentLink) ...[
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
              // Span bracket bar flush on the axis
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: isSelected ? itemColor : itemColor.withAlpha(200),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
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
    double Function(double) xForYear, {
    required bool isSelected,
  }) {
    final colors = context.ds;
    final itemColor = item.color.color;
    final centerX = xForYear(item.startYear);
    final containerHeight = (widget.trackHeight / 2) + 8; // Bottom at 88px (center at 81px)

    return Positioned(
      left: centerX - 60,
      top: 0,
      width: 120,
      height: containerHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          ref.read(timelineActionControllerProvider).selectItem(item.id);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
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
                    if (item.isDocumentLink) ...[
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
      ),
    );
  }
}
