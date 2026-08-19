/// Signing in, and who is signed in.
///
/// One rounded control in the top right: "Sign in" when signed out, the display
/// name when signed in, opening a small menu for the few things an account can
/// do. There is no account screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/knowledge_base/data/sharing.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/features/auth/data/auth_repository.dart';

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

    if (user == null) {
      return _RoundedButton(
        label: 'Sign in',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _SignInDialog(),
        ),
      );
    }

    return _RoundedButton(
      label: _labelFor(user, profile.valueOrNull),
      onPressed: () => _showAccountMenu(context, ref, user, profile),
    );
  }

  /// The display name if it could be read; otherwise what the account carries
  /// in its own metadata, which is set at sign-up and always present.
  String _labelFor(User user, Profile? profile) {
    if (profile != null) return profile.displayName;
    final metadata = user.userMetadata ?? const {};
    return (metadata['display_name'] as String?) ??
        (metadata['username'] as String?) ??
        'Account';
  }

  Future<void> _showAccountMenu(
    BuildContext context,
    WidgetRef ref,
    User user,
    AsyncValue<Profile?> profile,
  ) async {
    final colors = context.ds;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.control),
        side: BorderSide(color: colors.border),
      ),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 30,
          child: Text(
            '@${_usernameFor(user, profile.valueOrNull)}',
            style: aleo(size: 12, color: colors.muted),
          ),
        ),
        const PopupMenuDivider(height: 1),
        // A profile that could not be read is worth saying out loud rather
        // than quietly showing a fallback name.
        if (profile.hasError)
          PopupMenuItem<String>(
            value: 'error',
            height: 34,
            child: Text(
              'Could not load your profile',
              style: aleo(size: 13, color: colors.muted),
            ),
          ),
        PopupMenuItem<String>(
          value: 'name',
          height: 34,
          child: Text(
            'Change display name…',
            style: aleo(size: 13, color: colors.text),
          ),
        ),
        PopupMenuItem<String>(
          value: 'out',
          height: 34,
          child: Text('Sign out', style: aleo(size: 13, color: colors.text)),
        ),
      ],
    );

    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'name':
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _DisplayNameDialog(current: _labelFor(user, profile.valueOrNull)),
        );
      case 'error':
        await showDialog<void>(
          context: context,
          builder: (_) => DsDialog(
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close', style: aleo(size: 13, color: colors.text)),
              ),
            ],
            children: [DsErrorBox(describeError(profile.error!))],
          ),
        );
      case 'out':
        await ref.read(authRepositoryProvider).signOut();
        ref.invalidate(myProfileProvider);
    }
  }

  String _usernameFor(User user, Profile? profile) =>
      profile?.username ??
      (user.userMetadata?['username'] as String?) ??
      'unknown';
}

class _RoundedButton extends StatefulWidget {
  const _RoundedButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_RoundedButton> createState() => _RoundedButtonState();
}

class _RoundedButtonState extends State<_RoundedButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          // No alignment: a Container with one would stretch to fill the space
          // it is offered, and this control should hug its label.
          decoration: BoxDecoration(
            color: _hovered ? colors.selection : colors.island,
            borderRadius: const BorderRadius.all(DsRadius.control),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              widget.label,
              overflow: TextOverflow.ellipsis,
              style: aleo(size: 13, weight: 500, color: colors.text),
            ),
          ),
        ),
      ),
    );
  }
}

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
        TextButton(
          onPressed: () => setState(() => _creating = !_creating),
          child: Text(
            _creating ? 'I have an account' : 'Create an account',
            style: aleo(size: 13, color: colors.muted),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(
            _creating ? 'Create' : 'Sign in',
            style: aleo(size: 13, color: colors.text),
          ),
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
            style: aleo(size: 11, color: colors.muted),
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
        TextButton(
          onPressed: () async {
            await ref
                .read(authRepositoryProvider)
                .setDisplayName(_name.text.trim());
            ref.invalidate(myProfileProvider);
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text('Save', style: aleo(size: 13, color: colors.text)),
        ),
      ],
      children: [
        Text(
          'Collaborators see this name on every change you propose.',
          style: aleo(size: 12, color: colors.muted),
        ),
        const SizedBox(height: 8),
        DsField(controller: _name, hint: 'Display name'),
      ],
    );
  }
}
