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
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_sync_button.dart';
import 'package:path/path.dart' as p;

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
        _KbSwitcher(
          session: session,
          onPick: (path) async {
            await ref.read(kbControllerProvider.notifier).openFolder(path);
          },
        ),
        const SizedBox(height: 16),
        if (kbId != null && role != null && role != KbRole.local) ...[
          _SyncStatusRow(health: health),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
              label: _working ? 'Sharing…' : 'Share Knowledge Base',
              description: _working
                  ? 'Connecting to Supabase and publishing this Knowledge Base.'
                  : 'Creates the Supabase copy used for invitations, revisions '
                        'and Differences. Nothing is moved off this computer.',
              onPressed: _working ? null : _share,
            ),
          if (role == KbRole.local || role == KbRole.owner) ...[
            const SizedBox(height: 16),
            Text(
              'Danger Zone',
              style: uiTextStyle(size: 15, weight: 500, color: colors.text),
            ),
            const SizedBox(height: 8),
            DsSettingRow(
              key: const Key('delete-shared-knowledge-base-setting'),
              first: true,
              label: 'Delete Knowledge Base',
              helper:
                  'Deletes the Supabase copy and collaboration history, '
                  'but not your local files.',
              trailing: DsLabelButton(
                label: 'Delete',
                variant: DsButtonVariant.danger,
                height: DsSize.smallControl,
                horizontalPadding: 14,
                onPressed: _working ? null : _deleteShared,
              ),
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

/// Sync state and its one action. No card: a settings panel is already a
/// surface, and boxing a two-line row inside it only draws a second edge
/// around what the panel has already framed.
class _SyncStatusRow extends StatelessWidget {
  const _SyncStatusRow({required this.health});

  final SyncHealth health;

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
    return Padding(
      key: const Key('kb-sync-status-row'),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const KnowledgeBaseSyncButton(variant: DsButtonVariant.quiet),
          const SizedBox(width: 8),
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? colors.pending : colors.muted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: uiTextStyle(size: 11, color: colors.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
    CollaborationRole.editor,
    CollaborationRole.reviewer,
    if (currentRole == KbRole.owner) CollaborationRole.coOwner,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Column(
      key: const Key('kb-collaborators-card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Collaborators',
          style: uiTextStyle(size: 15, weight: 500, color: colors.text),
        ),
        const SizedBox(height: 8),
        collaborators.when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => DsErrorBox(describeError(error)),
          data: (members) {
            if (members.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No collaborators yet.',
                  style: uiTextStyle(size: 13, color: colors.muted),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < members.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: colors.sage,
                          child: Text(
                            members[i].displayName.isEmpty
                                ? '?'
                                : members[i].displayName[0].toUpperCase(),
                            style: uiTextStyle(
                              size: 12,
                              weight: 500,
                              color: colors.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                members[i].displayName,
                                overflow: TextOverflow.ellipsis,
                                style: uiTextStyle(
                                  size: 13,
                                  weight: 500,
                                  color: colors.text,
                                ),
                              ),
                              Text(
                                '@${members[i].username} · '
                                '${members[i].accepted ? members[i].role.label : 'Invited ${members[i].role.label}'}',
                                overflow: TextOverflow.ellipsis,
                                style: uiTextStyle(
                                  size: 11,
                                  color: colors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_canManage(members[i])) ...[
                          const SizedBox(width: 12),
                          DsSegmented<CollaborationRole>(
                            value: members[i].role,
                            cellHeight: 28,
                            onPick: (role) =>
                                onSetRole(members[i].userId, role),
                            options: [
                              for (final role in _rolesFor(members[i]))
                                DsSegmentedOption(
                                  value: role,
                                  semanticLabel: role.label,
                                  child: Text(role.label),
                                ),
                            ],
                          ),
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Remove ${members[i].displayName}',
                            child: DsButton(
                              variant: DsButtonVariant.quiet,
                              height: 28,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              semanticLabel:
                                  'Remove ${members[i].displayName}',
                              onPressed: () => onRemove(members[i].userId),
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: colors.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        if (onInvite != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                key: const Key('invite-collaborator-button'),
                onTap: onInvite,
                child: Text(
                  'Invite',
                  style: uiTextStyle(
                    size: 13,
                    weight: 500,
                    color: colors.link,
                  ).copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: colors.link,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    super.key,
    required this.label,
    required this.description,
    required this.onPressed,
  });

  final String label;
  final String description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

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
              color: onPressed == null ? colors.muted : colors.text,
            ),
          ),
          const SizedBox(height: 3),
          Text(description, style: uiTextStyle(size: 11, color: colors.muted)),
        ],
      ),
    );
  }
}

class _KbSwitcher extends ConsumerWidget {
  const _KbSwitcher({required this.session, required this.onPick});

  final KbSession? session;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final recentsAsync = ref.watch(recentKbPathsProvider);
    final currentPath = session?.kb.rootPath;
    final currentName = currentPath == null
        ? 'No Knowledge Base open'
        : p.basename(currentPath);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Knowledge Base',
          style: uiTextStyle(
            size: 15,
            weight: 500,
            color: colors.text,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Select a knowledge base',
                style: uiTextStyle(size: 13, color: colors.text),
              ),
            ),
            const SizedBox(width: 12),
            recentsAsync.when(
              data: (paths) {
                final items = paths.take(10).toList();
                if (items.isEmpty) {
                  return Text(
                    'No other Knowledge Bases',
                    style: uiTextStyle(size: 11, color: colors.muted),
                  );
                }
                return PopupMenuButton<String>(
                  tooltip: 'Switch Knowledge Base',
                  onSelected: onPick,
                  itemBuilder: (_) => [
                    for (final path in items)
                      PopupMenuItem(
                        value: path,
                        child: Text(
                          p.basename(path),
                          overflow: TextOverflow.ellipsis,
                          style: uiTextStyle(size: 13, color: colors.text),
                        ),
                      ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colors.island,
                      borderRadius: const BorderRadius.all(DsRadius.control),
                      border: Border.all(color: colors.surfaceOutline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentName,
                          style: uiTextStyle(size: 13, color: colors.text),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.expand_more,
                          size: 16,
                          color: colors.muted,
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (_, _) => const Icon(Icons.error_outline, size: 18),
            ),
          ],
        ),
      ],
    );
  }
}
