/// Visible editor controls for explicit collaboration publishing and document
/// protection.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/theme.dart';

Future<void> publishOpenDocumentWithFeedback(
  BuildContext context,
  WidgetRef ref,
) async {
  try {
    final result = await ref
        .read(sharingControllerProvider)
        .publishOpenDocument();
    if (result == SyncOutcome.committed) _recordPublished(ref);
  } on PublishConflict catch (conflict) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PublishConflictDialog(conflict: conflict),
    );
  } on Object catch (error) {
    ref
        .read(notificationStoreProvider.notifier)
        .record(DsNotificationKind.error, describeError(error));
  }
}

void _recordPublished(WidgetRef ref) {
  final open = ref.read(documentControllerProvider);
  if (open == null) return;
  ref
      .read(notificationStoreProvider.notifier)
      .record(DsNotificationKind.publish, 'Published "${open.document.title}"');
}

class DocumentPublishButton extends ConsumerWidget {
  const DocumentPublishButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(openDocumentPublishActionProvider);
    final openDocumentId = ref.watch(
      documentControllerProvider.select((open) => open?.document.id),
    );
    final sync = ref.watch(openDocumentReviewSyncProvider);
    final busy =
        sync?.phase == DifferenceSyncPhase.publishing ||
        sync?.phase == DifferenceSyncPhase.proposing;
    final value =
        action.isLoading || action.valueOrNull?.documentId != openDocumentId
        ? null
        : action.valueOrNull;
    final colors = context.ds;
    final label = value?.label ?? 'Publish';
    final tooltip = action.hasError
        ? describeError(action.error!)
        : value == null
        ? 'Publishing is unavailable for this document.'
        : '$label this document (${_shortcutLabel()})';

    return Tooltip(
      message: tooltip,
      child: DsButton(
        key: const Key('document-publish-button'),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        onPressed: value == null || busy
            ? null
            : () => unawaited(publishOpenDocumentWithFeedback(context, ref)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              value?.willPropose == true
                  ? Icons.outbox_outlined
                  : Icons.cloud_upload_outlined,
              size: 16,
              color: value == null ? colors.muted : colors.text,
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: uiTextStyle(
                size: 12,
                weight: 600,
                color: value == null ? colors.muted : colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentProtectionButton extends ConsumerWidget {
  const DocumentProtectionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(openDocumentPublishActionProvider);
    final openDocumentId = ref.watch(
      documentControllerProvider.select((open) => open?.document.id),
    );
    final value =
        action.isLoading || action.valueOrNull?.documentId != openDocumentId
        ? null
        : action.valueOrNull;
    final protection = value?.protection;
    final colors = context.ds;
    final tooltip = action.hasError
        ? describeError(action.error!)
        : protection == null
        ? 'Protect document'
        : 'Protected · ${protection.minimumPublishRole.label} required';
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 34,
        child: DsButton(
          key: const Key('document-protection-button'),
          height: 34,
          active: protection != null,
          padding: EdgeInsets.zero,
          onPressed: value == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => _DocumentProtectionDialog(action: value),
                ),
          child: Icon(
            protection == null ? Icons.shield_outlined : Icons.shield,
            size: 17,
            color: value == null ? colors.muted : colors.text,
          ),
        ),
      ),
    );
  }
}

class _DocumentProtectionDialog extends ConsumerStatefulWidget {
  const _DocumentProtectionDialog({required this.action});

  final OpenDocumentPublishAction action;

  @override
  ConsumerState<_DocumentProtectionDialog> createState() =>
      _DocumentProtectionDialogState();
}

class _DocumentProtectionDialogState
    extends ConsumerState<_DocumentProtectionDialog> {
  late MinimumPublishRole _minimumRole =
      widget.action.protection?.minimumPublishRole ??
      widget.action.role.minimumPublishRole!;
  String? _error;
  bool _saving = false;

  List<MinimumPublishRole> get _availableRoles => MinimumPublishRole.values
      .where(
        (role) =>
            role.rank <= widget.action.role.publishingRank! ||
            role == widget.action.protection?.minimumPublishRole,
      )
      .toList(growable: false);

  Future<void> _save(DocumentProtection? protection) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(sharingControllerProvider)
          .setDocumentProtection(
            documentId: widget.action.documentId,
            relativePath: widget.action.relativePath,
            protection: protection,
          );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canChange = widget.action.mayChangeProtection;
    final current = widget.action.protection;
    final colors = context.ds;
    return DsDialog(
      title: Text(
        current == null ? 'Protect document' : 'Document protection',
        style: uiHeaderTextStyle(color: colors.text),
      ),
      actions: [
        if (current != null)
          DsDialogAction(
            label: 'Unprotect',
            tone: DsDialogActionTone.muted,
            onPressed: canChange && !_saving ? () => _save(null) : null,
          ),
        DsDialogAction(
          label: current == null ? 'Protect' : 'Update',
          onPressed: canChange && !_saving
              ? () => _save(
                  DocumentProtection(
                    protectionClass: DocumentProtectionClass.protected,
                    minimumPublishRole: _minimumRole,
                  ),
                )
              : null,
        ),
      ],
      children: [
        Text(
          'People below the selected rank can still edit their local copy, '
          'but their explicit save is sent to Differences for review.',
          style: uiTextStyle(size: 12, color: colors.muted),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<DocumentProtectionClass>(
          key: const Key('protection-class-field'),
          initialValue: DocumentProtectionClass.protected,
          decoration: const InputDecoration(labelText: 'Protection class'),
          items: const [
            DropdownMenuItem(
              value: DocumentProtectionClass.protected,
              child: Text('Protected'),
            ),
          ],
          onChanged: canChange ? (_) {} : null,
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<MinimumPublishRole>(
          key: const Key('minimum-publish-role-field'),
          initialValue: _minimumRole,
          decoration: const InputDecoration(
            labelText: 'Access needed to publish',
          ),
          items: [
            for (final role in _availableRoles)
              DropdownMenuItem(value: role, child: Text(role.label)),
          ],
          onChanged: canChange
              ? (value) {
                  if (value != null) setState(() => _minimumRole = value);
                }
              : null,
        ),
        if (!canChange) ...[
          const SizedBox(height: 12),
          Text(
            '${current!.minimumPublishRole.label} access is required to change '
            'this protection.',
            style: uiTextStyle(size: 12, color: colors.muted),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          DsErrorBox(_error!),
        ],
      ],
    );
  }
}

class _PublishConflictDialog extends ConsumerStatefulWidget {
  const _PublishConflictDialog({required this.conflict});

  final PublishConflict conflict;

  @override
  ConsumerState<_PublishConflictDialog> createState() =>
      _PublishConflictDialogState();
}

class _PublishConflictDialogState
    extends ConsumerState<_PublishConflictDialog> {
  String? _error;
  bool _resolving = false;

  Future<void> _resolve(bool publishLocal) async {
    setState(() {
      _resolving = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(sharingControllerProvider)
          .resolvePublishConflict(widget.conflict, publishLocal: publishLocal);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (result == SyncOutcome.committed) _recordPublished(ref);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = describeError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsDialog(
      title: Text(
        'Resolve publish conflict',
        style: uiHeaderTextStyle(color: colors.text),
      ),
      actions: [
        DsDialogAction(
          label: 'Use collaborator version',
          tone: DsDialogActionTone.muted,
          onPressed: _resolving ? null : () => _resolve(false),
        ),
        DsDialogAction(
          label: 'Publish my version',
          onPressed: _resolving ? null : () => _resolve(true),
        ),
      ],
      children: [
        Text(
          'Both versions changed the same content. Your local copy has not '
          'been overwritten. Choose which version should become canonical, or '
          'close this window to keep working locally.',
          style: uiTextStyle(size: 12, color: colors.muted),
        ),
        if (widget.conflict.pathConflict) ...[
          const SizedBox(height: 8),
          Text(
            'The document was also renamed differently on both copies.',
            style: uiTextStyle(size: 12, color: colors.conflict),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          DsErrorBox(_error!),
        ],
      ],
    );
  }
}

String _shortcutLabel() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘S' : 'Ctrl+S';
