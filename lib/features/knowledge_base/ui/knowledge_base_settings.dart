/// Settings for the connection between an on-disk Knowledge Base and its
/// optional Supabase mirror.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/theme.dart';

const double kKnowledgeBaseControlHeight = 38;

/// The compact gear beside the active Knowledge Base selector.
class KnowledgeBaseSettingsButton extends ConsumerWidget {
  const KnowledgeBaseSettingsButton({super.key});

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
          onPressed: session == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => const _KnowledgeBaseSettingsDialog(),
                ),
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

class _KnowledgeBaseSettingsDialog extends ConsumerStatefulWidget {
  const _KnowledgeBaseSettingsDialog();

  @override
  ConsumerState<_KnowledgeBaseSettingsDialog> createState() =>
      _KnowledgeBaseSettingsDialogState();
}

class _KnowledgeBaseSettingsDialogState
    extends ConsumerState<_KnowledgeBaseSettingsDialog> {
  bool _working = false;
  String? _error;

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref.read(sharingControllerProvider).shareOpenKb();
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Knowledge Base is now shared.')),
      );
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
          style: uiTextStyle(size: 16, weight: 600, color: colors.text),
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

    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref.read(sharingControllerProvider).deleteSharedKb();
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Supabase connection removed. Local files were not changed.',
          ),
        ),
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

    return DsDialog(
      width: 400,
      title: Text(
        'Knowledge Base Settings',
        style: uiTextStyle(size: 16, weight: 600, color: colors.text),
      ),
      actions: [
        DsDialogAction(
          label: 'Done',
          onPressed: _working ? null : () => Navigator.of(context).pop(),
          tone: DsDialogActionTone.muted,
        ),
      ],
      children: [
        Text(
          'Sharing connects this on-disk Knowledge Base to Supabase for '
          'invitations and reviewed collaboration. The local folder remains '
          'the Knowledge Base you work in.',
          style: uiTextStyle(size: 13, color: colors.muted),
        ),
        const SizedBox(height: 12),
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
        ? Theme.of(context).colorScheme.error
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
              weight: 600,
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
