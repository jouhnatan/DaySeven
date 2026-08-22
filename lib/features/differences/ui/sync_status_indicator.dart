/// Compact reviewed-edit network state shown beside the editor toolbar menu.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DocumentReviewSyncIndicator extends ConsumerWidget {
  const DocumentReviewSyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(openDocumentReviewSyncProvider);
    if (status == null) return const SizedBox.shrink();
    final colors = context.ds;
    final color = switch (status.phase) {
      DifferenceSyncPhase.waitingForReview => colors.pending,
      DifferenceSyncPhase.offline => colors.muted,
      DifferenceSyncPhase.conflict => colors.conflict,
      DifferenceSyncPhase.error => colors.removal,
      DifferenceSyncPhase.savingLocally ||
      DifferenceSyncPhase.syncingForReview => colors.link,
      DifferenceSyncPhase.synced => colors.muted,
    };
    return Tooltip(
      message: status.detail == null
          ? status.label
          : '${status.label}: ${status.detail}',
      child: Semantics(
        liveRegion: true,
        label: status.label,
        child: Row(
          key: const Key('document-review-sync-status'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(status.label, style: uiTextStyle(size: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
