/// Inviting a collaborator to the open Knowledge Base.
///
/// Sharing belongs to the Knowledge Base rather than to the account, so this
/// opens from the Knowledge Base dropdown rather than from the sign-in button.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/knowledge_base/data/sharing.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';

class InviteDialog extends ConsumerStatefulWidget {
  const InviteDialog({super.key});

  @override
  ConsumerState<InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<InviteDialog> {
  final _username = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    setState(() => _error = null);
    try {
      await ref.read(sharingControllerProvider).invite(_username.text.trim());
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsDialog(
      actions: [
        TextButton(
          onPressed: _invite,
          child: Text('Invite', style: aleo(size: 13, color: colors.text)),
        ),
      ],
      children: [
        Text(
          'They choose their own folder for this Knowledge Base.',
          style: aleo(size: 12, color: colors.muted),
        ),
        const SizedBox(height: 8),
        DsField(controller: _username, hint: 'Username'),
        if (_error != null) DsErrorBox(_error!),
      ],
    );
  }
}
