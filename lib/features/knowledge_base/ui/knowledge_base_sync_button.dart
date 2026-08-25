/// Manual synchronization for the open shared Knowledge Base.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_settings.dart';

/// The compact sync control between the active Knowledge Base and its settings.
class KnowledgeBaseSyncButton extends ConsumerStatefulWidget {
  const KnowledgeBaseSyncButton({super.key});

  @override
  ConsumerState<KnowledgeBaseSyncButton> createState() =>
      _KnowledgeBaseSyncButtonState();
}

class _KnowledgeBaseSyncButtonState
    extends ConsumerState<KnowledgeBaseSyncButton> {
  bool _syncing = false;

  Future<void> _sync(KbRole role) async {
    if (_syncing) return;
    setState(() => _syncing = true);

    final notifications = ref.read(notificationStoreProvider.notifier);
    try {
      final sharing = ref.read(sharingControllerProvider);
      final message = role == KbRole.reviewer
          ? _describePull(await sharing.pullRemoteChanges())
          : _describeReconcile(await sharing.reconcileHierarchy());
      notifications.record(DsNotificationKind.sync, message);
    } catch (error) {
      notifications.record(DsNotificationKind.error, describeError(error));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(kbSessionProvider);
    final role = ref.watch(kbRoleProvider).valueOrNull;
    final canSync =
        session != null &&
        role != null &&
        role != KbRole.local &&
        role != KbRole.invited;
    final colors = context.ds;

    return Tooltip(
      message: _syncing ? 'Syncing Knowledge Base' : 'Sync Knowledge Base',
      child: SizedBox.square(
        dimension: kKnowledgeBaseControlHeight,
        child: DsButton(
          key: const Key('knowledge-base-sync-button'),
          onPressed: canSync && !_syncing ? () => _sync(role) : null,
          highlight: colors.selection,
          height: kKnowledgeBaseControlHeight,
          padding: EdgeInsets.zero,
          borderRadius: const BorderRadius.all(DsRadius.island),
          child: _syncing
              ? SizedBox.square(
                  dimension: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: colors.muted,
                  ),
                )
              : Icon(
                  Icons.sync,
                  size: 17,
                  color: canSync ? colors.text : colors.muted,
                ),
        ),
      ),
    );
  }
}

String _describePull(SyncPullResult result) {
  final parts = <String>['${result.updated} pulled'];
  if (result.recoveredDeletions > 0) {
    parts.add('${result.recoveredDeletions} recovered deletion(s)');
  }
  if (result.conflicts > 0) {
    parts.add('${result.conflicts} pull conflict(s) left untouched');
  }
  return parts.join(' · ');
}

String _describeReconcile(ReconcileResult result) {
  final parts = <String>[
    '${result.pull.updated} pulled',
    '${result.push.published} published',
  ];
  if (result.push.proposed > 0) {
    parts.add('${result.push.proposed} proposed');
  }
  if (result.pull.recoveredDeletions > 0) {
    parts.add('${result.pull.recoveredDeletions} recovered deletion(s)');
  }
  if (result.pull.conflicts > 0) {
    parts.add('${result.pull.conflicts} pull conflict(s) left untouched');
  }
  if (result.push.conflicts > 0) {
    parts.add('${result.push.conflicts} publish conflict(s) left untouched');
  }
  return parts.join(' · ');
}
