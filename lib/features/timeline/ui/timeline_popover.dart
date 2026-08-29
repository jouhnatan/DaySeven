/// Detail popover card displaying an event or period's metadata and description/KB link.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelinePopover extends ConsumerWidget {
  const TimelinePopover({
    super.key,
    required this.item,
    required this.onClose,
  });

  final TimelineItem item;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;

    final dateSpan = switch (item) {
      final TimelinePeriodItem p => '${p.startDateLabel} → ${p.endDateLabel}',
      final TimelineEventItem e => e.startDateLabel,
    };

    return Container(
      constraints: const BoxConstraints(maxWidth: 380, minWidth: 260),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.island,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: colors.surfaceOutline),
        boxShadow: cfMenuShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Title, Color dot, and Close button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5, right: 8),
                decoration: BoxDecoration(
                  color: item.color.color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title.isEmpty ? 'Untitled' : item.title,
                      style: uiTextStyle(
                        size: 15,
                        weight: 600,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateSpan,
                      style: uiTextStyle(
                        size: 12,
                        color: colors.muted,
                        tabular: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClose,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 16, color: colors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Body: Either Knowledge Base Document Link OR Description text
          if (item.isDocumentLink) ...[
            Text(
              'Linked Document',
              style: uiTextStyle(size: 11.5, weight: 500, color: colors.muted),
            ),
            const SizedBox(height: 6),
            DsButton(
              variant: DsButtonVariant.secondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onPressed: () {
                ref
                    .read(documentControllerProvider.notifier)
                    .open(item.kbDocumentPath!);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 16, color: colors.link),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.kbDocumentPath!,
                      overflow: TextOverflow.ellipsis,
                      style: uiTextStyle(
                        size: 13,
                        color: colors.link,
                        weight: 500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: colors.muted),
                ],
              ),
            ),
          ] else if (item.description.isNotEmpty) ...[
            Text(
              item.description,
              style: uiTextStyle(
                size: 13,
                height: 1.5,
                color: colors.text,
              ),
            ),
          ] else ...[
            Text(
              'No description provided.',
              style: uiTextStyle(size: 13, color: colors.faint),
            ),
          ],
        ],
      ),
    );
  }
}
