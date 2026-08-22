/// Inviting a collaborator to the open Knowledge Base.
///
/// Sharing belongs to the Knowledge Base rather than to the account, so this
/// opens from the Knowledge Base dropdown rather than from the sign-in button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/features/knowledge_base/data/kb_repository.dart';

class InviteDialog extends ConsumerStatefulWidget {
  const InviteDialog({super.key, this.allowCoOwner = false});

  final bool allowCoOwner;

  @override
  ConsumerState<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<InviteDialog> {
  final _username = TextEditingController();
  String? _error;
  CollaborationRole _role = CollaborationRole.editor;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    setState(() => _error = null);
    try {
      await ref
          .read(sharingControllerProvider)
          .invite(_username.text.trim(), _role);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsDialog(
      actions: [DsDialogAction(label: 'Invite', onPressed: _invite)],
      children: [
        Text(
          'They choose their own folder for this Knowledge Base.',
          style: uiTextStyle(size: 12, color: colors.muted),
        ),
        const SizedBox(height: 8),
        DsField(controller: _username, hint: 'Username'),
        const SizedBox(height: 8),
        DropdownButtonFormField<CollaborationRole>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role'),
          items: [
            const DropdownMenuItem(
              value: CollaborationRole.editor,
              child: Text('Editor'),
            ),
            const DropdownMenuItem(
              value: CollaborationRole.reviewer,
              child: Text('Reviewer'),
            ),
            if (widget.allowCoOwner)
              const DropdownMenuItem(
                value: CollaborationRole.coOwner,
                child: Text('Co-Owner'),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _role = value);
          },
        ),
        if (_error != null) DsErrorBox(_error!),
      ],
    );
  }
}
