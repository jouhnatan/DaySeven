/// Signing in, and who is signed in.
///
/// One rounded control in the top right: "Sign in" when signed out, the display
/// name when signed in, opening a small menu for the few things an account can
/// do. There is no account screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';

enum _AccountAction { profileError, changeName, signOut }

class AuthButton extends ConsumerWidget {
  const AuthButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Being signed in is a fact about the session, not about whether the
    // profile row could be read. Keying this off the profile meant any failure
    // to fetch it — a dropped request, a stale schema cache — showed the
    // person as signed out while they were signed in.
    final user = ref.watch(currentUserProvider);
    final profile = ref.watch(myProfileProvider);
    final displayName = ref.watch(accountDisplayNameProvider);

    if (user == null) {
      return DsLabelButton(
        label: 'Sign in',
        onPressed: () => showSignInDialog(context),
      );
    }

    return DsLabelButton(
      label: displayName ?? 'Account',
      highlight: context.ds.selection,
      onPressed: () => _showAccountMenu(
        context,
        ref,
        user,
        profile,
        displayName ?? 'Account',
      ),
    );
  }

  Future<void> _showAccountMenu(
    BuildContext context,
    WidgetRef ref,
    User user,
    AsyncValue<Profile?> profile,
    String displayName,
  ) async {
    final colors = context.ds;
    final choice = await showDsMenu<_AccountAction>(
      context: context,
      items: [
        DsMenuItem<_AccountAction>(
          enabled: false,
          height: kDsMenuHeaderHeight,
          child: Text(
            '@${_usernameFor(user, profile.valueOrNull)}',
            style: uiTextStyle(size: 12, color: colors.muted),
          ),
        ),
        const DsMenuDivider(),
        // A profile that could not be read is worth saying out loud rather
        // than quietly showing a fallback name.
        if (profile.hasError)
          DsMenuItem<_AccountAction>(
            value: _AccountAction.profileError,
            height: kDsMenuItemHeight,
            child: Text(
              'Could not load your profile',
              style: uiTextStyle(size: 13, color: colors.muted),
            ),
          ),
        DsMenuItem<_AccountAction>(
          value: _AccountAction.changeName,
          height: kDsMenuItemHeight,
          child: Text(
            'Change display name…',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        DsMenuItem<_AccountAction>(
          value: _AccountAction.signOut,
          height: kDsMenuItemHeight,
          child: Text(
            'Sign out',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
      ],
    );

    if (choice == null || !context.mounted) return;

    switch (choice) {
      case _AccountAction.changeName:
        await showDialog<void>(
          context: context,
          builder: (_) => _DisplayNameDialog(current: displayName),
        );
      case _AccountAction.profileError:
        await showDialog<void>(
          context: context,
          builder: (_) => DsDialog(
            actions: [
              DsDialogAction(
                label: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
            children: [DsErrorBox(describeError(profile.error!))],
          ),
        );
      case _AccountAction.signOut:
        await ref.read(authRepositoryProvider).signOut();
        ref.invalidate(myProfileProvider);
    }
  }

  String _usernameFor(User user, Profile? profile) =>
      profile?.username ??
      (user.userMetadata?['username'] as String?) ??
      'unknown';
}

Future<void> showSignInDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SignInDialog());

class _SignInDialog extends ConsumerStatefulWidget {
  const _SignInDialog();

  @override
  ConsumerState<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends ConsumerState<_SignInDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    try {
      final auth = ref.read(authRepositoryProvider);
      if (_creating) {
        await auth.signUp(
          _username.text,
          _password.text,
          _displayName.text.trim(),
        );
      } else {
        await auth.signIn(_username.text, _password.text);
      }
      ref.invalidate(myProfileProvider);
      ref.invalidate(kbRoleProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsDialog(
      actions: [
        DsDialogAction(
          label: _creating ? 'I have an account' : 'Create an account',
          onPressed: () => setState(() => _creating = !_creating),
          tone: DsDialogActionTone.muted,
        ),
        DsDialogAction(
          label: _creating ? 'Create' : 'Sign in',
          onPressed: _submit,
        ),
      ],
      children: [
        DsField(controller: _username, hint: 'Username'),
        DsField(controller: _password, hint: 'Password', obscure: true),
        if (_creating) ...[
          DsField(controller: _displayName, hint: 'Display name (optional)'),
          Text(
            'Your username is how collaborators invite you. '
            'Your display name is what they see on a proposal.',
            style: uiTextStyle(size: 11, color: colors.muted),
          ),
          const SizedBox(height: 6),
        ],
        if (_error != null) DsErrorBox(_error!),
      ],
    );
  }
}

class _DisplayNameDialog extends ConsumerStatefulWidget {
  const _DisplayNameDialog({required this.current});

  final String current;

  @override
  ConsumerState<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends ConsumerState<_DisplayNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsDialog(
      actions: [
        DsDialogAction(
          label: 'Save',
          onPressed: () async {
            await ref
                .read(authRepositoryProvider)
                .setDisplayName(_name.text.trim());
            ref.invalidate(myProfileProvider);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
      children: [
        Text(
          'Collaborators see this name on every change you propose.',
          style: uiTextStyle(size: 12, color: colors.muted),
        ),
        const SizedBox(height: 8),
        DsField(controller: _name, hint: 'Display name'),
      ],
    );
  }
}
