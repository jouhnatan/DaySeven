/// Settings for the connection between an on-disk Knowledge Base and its
/// optional Supabase mirror.
///
/// These live inside App settings rather than in a dialog of their own: they
/// are settings, and the application has one place for those. What is left
/// here is the panel itself and the gear that opens App settings on it, so
/// that managing the open Knowledge Base is still one click from the tree.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/knowledge_base/data/kb_repository.dart';
import 'package:dayseven/features/knowledge_base/ui/invite_dialog.dart';

const double kKnowledgeBaseControlHeight = 38;

/// The compact gear beside the active Knowledge Base selector.
class KnowledgeBaseSettingsButton extends ConsumerWidget {
  const KnowledgeBaseSettingsButton({super.key, this.onPressed});

  /// Opens App settings on the Knowledge Base section. It is supplied from
  /// above rather than called from here: App settings belongs to another
  /// feature, and a feature does not reach into one of its siblings.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kbSessionProvider);
    final colors = context.ds;

    return Tooltip(
      message: 'Knowledge Base settings',
      child: SizedBox.square(
        dimension: kKnowledgeBaseControlHeight,
        child: DsButton(
          key: const Key('knowledge-base-settings-button'),
          semanticLabel: 'Knowledge Base settings',
          onPressed: session == null ? null : onPressed,
          highlight: colors.selection,
          height: kKnowledgeBaseControlHeight,
          padding: EdgeInsets.zero,
          borderRadius: const BorderRadius.all(DsRadius.island),
          child: Icon(
            Icons.settings_outlined,
            size: 17,
            color: session == null ? colors.muted : colors.text,
          ),
        ),
      ),
    );
  }
}

/// The Knowledge Base section of App settings.
class KnowledgeBaseSettingsPanel extends ConsumerStatefulWidget {
  const KnowledgeBaseSettingsPanel({super.key});

  @override
  ConsumerState<KnowledgeBaseSettingsPanel> createState() =>
      _KnowledgeBaseSettingsPanelState();
}

class _KnowledgeBaseSettingsPanelState
    extends ConsumerState<KnowledgeBaseSettingsPanel> {
  bool _working = false;
  String? _error;

  Future<void> _setRole(
    String kbId,
    String userId,
    CollaborationRole role,
  ) async {
    try {
      await ref
          .read(sharingControllerProvider)
          .setCollaboratorRole(kbId: kbId, userId: userId, role: role);
      ref.invalidate(kbCollaboratorsProvider(kbId));
      ref.invalidate(kbRoleProvider);
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  Future<void> _removeMember(String kbId, String userId) async {
    try {
      await ref
          .read(sharingControllerProvider)
          .removeCollaborator(kbId: kbId, userId: userId);
      ref.invalidate(kbCollaboratorsProvider(kbId));
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  Future<void> _share() async {
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref.read(sharingControllerProvider).shareOpenKb();
      if (!mounted) return;
      setState(() => _working = false);
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.share, 'Knowledge Base is now shared.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = describeError(error);
      });
    }
  }

  Future<void> _deleteShared() async {
    final colors = context.ds;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DsDialog(
        title: Text(
          'Delete shared Knowledge Base?',
          style: uiTextStyle(size: 16, weight: 500, color: colors.text),
        ),
        actions: [
          DsDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
            tone: DsDialogActionTone.muted,
          ),
          DsDialogAction(
            label: 'Delete Shared Knowledge Base',
            onPressed: () => Navigator.of(dialogContext).pop(true),
            tone: DsDialogActionTone.danger,
          ),
        ],
        children: [
          Text(
            'This permanently deletes the Supabase copy, invitations, '
            'revision history and pending proposals. It does not delete or '
            'change the Knowledge Base folder or any files on this computer. '
            'You can share it again later.',
            style: uiTextStyle(size: 13, color: colors.muted),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref.read(sharingControllerProvider).deleteSharedKb();
      if (!mounted) return;
      setState(() => _working = false);
      ref
          .read(notificationStoreProvider.notifier)
          .record(
            DsNotificationKind.share,
            'Supabase connection removed. Local files were not changed.',
          );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _error = describeError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final user = ref.watch(currentUserProvider);
    final role = ref.watch(kbRoleProvider).valueOrNull;
    final session = ref.watch(kbSessionProvider);
    final canManage = user != null && session != null;
    final kbId = session?.kb.manifest.kbId;
    final collaborators = kbId == null
        ? const AsyncValue<List<KbCollaborator>>.data([])
        : ref.watch(kbCollaboratorsProvider(kbId));
    final health = kbId == null
        ? SyncHealth.inactive
        : ref.watch(kbSyncHealthProvider(kbId)).valueOrNull ??
              SyncHealth.checking;

    return Column(
      key: const Key('knowledge-base-settings-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Sharing connects this on-disk Knowledge Base to Supabase for '
          'invitations and reviewed collaboration. The local folder remains '
          'the Knowledge Base you work in.',
          style: uiTextStyle(size: 13, color: colors.muted),
        ),
        const SizedBox(height: 12),
        if (kbId != null && role != null && role != KbRole.local) ...[
          _SyncStatusCard(
            health: health,
            onRetry: () => ref.invalidate(kbSyncHealthProvider(kbId)),
          ),
          const SizedBox(height: 12),
          _CollaboratorsCard(
            collaborators: collaborators,
            currentRole: role,
            onSetRole: (userId, next) => _setRole(kbId, userId, next),
            onRemove: (userId) => _removeMember(kbId, userId),
            onInvite: role == KbRole.owner || role == KbRole.coOwner
                ? () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) =>
                          InviteDialog(allowCoOwner: role == KbRole.owner),
                    );
                    ref.invalidate(kbCollaboratorsProvider(kbId));
                  }
                : null,
          ),
          const SizedBox(height: 12),
        ],
        if (!canManage)
          Text(
            'Sign in to share or manage this Knowledge Base connection.',
            style: uiTextStyle(size: 13, color: colors.muted),
          )
        else if (role == KbRole.invited)
          Text(
            'Accept the invitation from the Knowledge Base menu before '
            'collaborating. Only its owner can delete the shared copy.',
            style: uiTextStyle(size: 13, color: colors.muted),
          )
        else if (role == KbRole.editor)
          Text(
            'This Knowledge Base is shared by its owner. Your edits can be '
            'proposed for review, but only the owner can delete the shared copy.',
            style: uiTextStyle(size: 13, color: colors.muted),
          )
        else if (role == KbRole.reviewer)
          Text(
            'You can review proposed changes. Document editing is read-only.',
            style: uiTextStyle(size: 13, color: colors.muted),
          )
        else if (role == KbRole.coOwner)
          Text(
            'You can edit, review, invite Editors and Reviewers, and manage '
            'their access. Only the Owner controls Co-Owners and deletion.',
            style: uiTextStyle(size: 13, color: colors.muted),
          )
        else ...[
          if (role == KbRole.local)
            _SettingsAction(
              key: const Key('share-knowledge-base-setting'),
              label: 'Share Knowledge Base',
              description:
                  'Creates the Supabase copy used for invitations, revisions '
                  'and Differences. Nothing is moved off this computer.',
              onPressed: _working ? null : _share,
            ),
          if (role == KbRole.owner)
            Text(
              'This Knowledge Base is connected to Supabase and you are its owner.',
              style: uiTextStyle(size: 13, color: colors.muted),
            ),
          if (role == KbRole.local || role == KbRole.owner) ...[
            const SizedBox(height: 8),
            _SettingsAction(
              key: const Key('delete-shared-knowledge-base-setting'),
              label: 'Delete Shared Knowledge Base',
              description:
                  'Deletes only the Supabase copy and collaboration history. '
                  'The on-disk Knowledge Base is not deleted or changed, and '
                  'you can share it again later.',
              danger: true,
              onPressed: _working ? null : _deleteShared,
            ),
          ],
        ],
        if (_working) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          DsErrorBox(_error!),
        ],
      ],
    );
  }
}

class _SyncStatusCard extends StatelessWidget {
  const _SyncStatusCard({required this.health, required this.onRetry});

  final SyncHealth health;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final active = health == SyncHealth.active;
    final label = switch (health) {
      SyncHealth.active => 'Active',
      SyncHealth.checking => 'Checking…',
      SyncHealth.offline => 'Inactive · Offline',
      SyncHealth.unauthorized => 'Inactive · Access removed',
      SyncHealth.error => 'Inactive · Error',
      SyncHealth.inactive => 'Inactive',
    };
    return DsCard(
      key: const Key('kb-sync-status-card'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? colors.pending : colors.muted,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sync',
                    style: uiTextStyle(
                      size: 13,
                      weight: 500,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    label,
                    style: uiTextStyle(size: 11, color: colors.muted),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _CollaboratorsCard extends StatelessWidget {
  const _CollaboratorsCard({
    required this.collaborators,
    required this.currentRole,
    required this.onSetRole,
    required this.onRemove,
    required this.onInvite,
  });

  final AsyncValue<List<KbCollaborator>> collaborators;
  final KbRole currentRole;
  final Future<void> Function(String, CollaborationRole) onSetRole;
  final Future<void> Function(String) onRemove;
  final VoidCallback? onInvite;

  bool _canManage(KbCollaborator member) => switch (currentRole) {
    KbRole.owner => member.role != CollaborationRole.owner,
    KbRole.coOwner =>
      member.role == CollaborationRole.editor ||
          member.role == CollaborationRole.reviewer,
    _ => false,
  };

  List<CollaborationRole> _rolesFor(KbCollaborator member) => [
    if (currentRole == KbRole.owner) CollaborationRole.coOwner,
    CollaborationRole.editor,
    CollaborationRole.reviewer,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsCard(
      key: const Key('kb-collaborators-card'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Collaborators',
                    style: uiTextStyle(
                      size: 13,
                      weight: 500,
                      color: colors.text,
                    ),
                  ),
                ),
                if (onInvite != null)
                  TextButton(onPressed: onInvite, child: const Text('Invite')),
              ],
            ),
            const SizedBox(height: 8),
            collaborators.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => DsErrorBox(describeError(error)),
              data: (members) => LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final member in members)
                      SizedBox(
                        width: constraints.maxWidth >= 560
                            ? (constraints.maxWidth - 8) / 2
                            : constraints.maxWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.selection,
                            borderRadius: const BorderRadius.all(
                              DsRadius.control,
                            ),
                            border: Border.all(color: colors.border),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 15,
                                  backgroundColor: colors.sage,
                                  child: Text(
                                    member.displayName.isEmpty
                                        ? '?'
                                        : member.displayName[0].toUpperCase(),
                                    style: uiTextStyle(
                                      size: 12,
                                      weight: 500,
                                      color: colors.text,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member.displayName,
                                        overflow: TextOverflow.ellipsis,
                                        style: uiTextStyle(
                                          size: 12,
                                          weight: 500,
                                          color: colors.text,
                                        ),
                                      ),
                                      Text(
                                        '@${member.username} · '
                                        '${member.accepted ? member.role.label : 'Invited ${member.role.label}'}',
                                        overflow: TextOverflow.ellipsis,
                                        style: uiTextStyle(
                                          size: 10,
                                          color: colors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_canManage(member))
                                  PopupMenuButton<Object>(
                                    tooltip: 'Manage collaborator',
                                    itemBuilder: (_) => [
                                      for (final role in _rolesFor(member))
                                        PopupMenuItem<Object>(
                                          value: role,
                                          child: Text(role.label),
                                        ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem<Object>(
                                        value: 'remove',
                                        child: Text('Remove'),
                                      ),
                                    ],
                                    onSelected: (value) {
                                      if (value == 'remove') {
                                        onRemove(member.userId);
                                      } else if (value is CollaborationRole) {
                                        onSetRole(member.userId, value);
                                      }
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    super.key,
    required this.label,
    required this.description,
    required this.onPressed,
    this.danger = false,
  });

  final String label;
  final String description;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final labelColor = danger
        ? colors.danger
        : colors.text;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(DsRadius.control),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: uiTextStyle(
              size: 13,
              weight: 500,
              color: onPressed == null ? colors.muted : labelColor,
            ),
          ),
          const SizedBox(height: 3),
          Text(description, style: uiTextStyle(size: 11, color: colors.muted)),
        ],
      ),
    );
  }
}
