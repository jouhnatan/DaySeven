import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/view.dart';
import '../../../app/workspace/kb_session.dart';
import '../../../app/workspace/open_document.dart';
import '../../../app/workspace/sharing.dart';
import '../../../shared/auth/auth_repository.dart';
import '../../../shared/backend/supabase_client.dart';
import '../../../shared/ui/controls.dart';
import '../../../shared/ui/error_box.dart';
import '../../../shared/ui/theme.dart';
import '../../auth/ui/auth_button.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _loggingOut = false;
  String? _accountError;

  Future<void> _openRecent(String path) async {
    await ref.read(documentControllerProvider.notifier).open(path);
    ref.read(viewProvider.notifier).state = DsView.editor;
  }

  Future<void> _logOut() async {
    setState(() {
      _accountError = null;
      _loggingOut = true;
    });

    try {
      await ref.read(authRepositoryProvider).signOut();
      ref.invalidate(myProfileProvider);
      ref.invalidate(kbRoleProvider);
    } catch (error) {
      if (mounted) {
        setState(() => _accountError = describeError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final session = ref.watch(kbSessionProvider);
    final recents = ref.watch(recentEditedDocumentsProvider);
    final user = ref.watch(currentUserProvider);
    final displayName = ref.watch(accountDisplayNameProvider);
    final greetingName = displayName ?? 'Guest';

    return Stack(
      key: const Key('home-gradient'),
      fit: StackFit.expand,
      children: [
        LayoutBuilder(
          builder: (context, _) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Ready to build, $greetingName?',
                        key: const Key('home-greeting'),
                        textAlign: TextAlign.center,
                        style: uiHeaderTextStyle(
                          size: 32,
                          weight: 600,
                          color: colors.text,
                        ),
                      ),
                      const SizedBox(height: 40),
                      LayoutBuilder(
                        builder: (context, content) {
                          final recentCard = _HomeCard(
                            key: const Key('home-recent-files-card'),
                            title: 'Recent Files',
                            child: _RecentFiles(
                              hasKnowledgeBase: session != null,
                              recents: recents,
                              onOpen: _openRecent,
                            ),
                          );
                          final settingsCard = _HomeCard(
                            key: const Key('home-user-settings-card'),
                            title: 'User Settings',
                            child: _UserSettings(
                              signedIn: user != null,
                              displayName: displayName,
                              loggingOut: _loggingOut,
                              error: _accountError,
                              onSignIn: () => showSignInDialog(context),
                              onLogOut: _logOut,
                            ),
                          );

                          if (content.maxWidth < 720) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                recentCard,
                                const SizedBox(height: 16),
                                settingsCard,
                              ],
                            );
                          }

                          return IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: recentCard),
                                const SizedBox(width: 16),
                                Expanded(child: settingsCard),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? colors.island.withValues(alpha: 0.84)
            : Colors.white.withValues(alpha: 0.82),
        border: Border.all(color: colors.surfaceOutline),
        borderRadius: const BorderRadius.all(DsRadius.island),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.16 : 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: uiHeaderTextStyle(
                size: 18,
                weight: 600,
                color: colors.text,
              ),
            ),
            const SizedBox(height: 18),
            child,
          ],
        ),
      ),
    );
  }
}

class _RecentFiles extends StatelessWidget {
  const _RecentFiles({
    required this.hasKnowledgeBase,
    required this.recents,
    required this.onOpen,
  });

  final bool hasKnowledgeBase;
  final AsyncValue<List<String>> recents;
  final Future<void> Function(String path) onOpen;

  @override
  Widget build(BuildContext context) {
    if (!hasKnowledgeBase) {
      return const _EmptyCardMessage('Open a Knowledge Base to begin.');
    }

    return recents.when(
      loading: () => const _EmptyCardMessage('Loading recent files…'),
      error: (error, stackTrace) => DsErrorBox(describeError(error)),
      data: (paths) {
        if (paths.isEmpty) {
          return const _EmptyCardMessage('No edited files yet.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final path in paths)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _HomeLinkRow(
                  key: Key('recent-file-$path'),
                  label: p.basename(path),
                  detail: p.dirname(path) == '.' ? null : p.dirname(path),
                  onTap: () => onOpen(path),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UserSettings extends StatelessWidget {
  const _UserSettings({
    required this.signedIn,
    required this.displayName,
    required this.loggingOut,
    required this.error,
    required this.onSignIn,
    required this.onLogOut,
  });

  final bool signedIn;
  final String? displayName;
  final bool loggingOut;
  final String? error;
  final VoidCallback onSignIn;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (signedIn) ...[
          Text(
            'Display name',
            textAlign: TextAlign.left,
            style: uiTextStyle(size: 12, weight: 600, color: colors.muted),
          ),
          const SizedBox(height: 4),
          Text(
            displayName ?? 'Account',
            key: const Key('home-display-name'),
            textAlign: TextAlign.left,
            style: uiTextStyle(size: 14, weight: 600, color: colors.text),
          ),
          const SizedBox(height: 12),
          _HomeLinkRow(
            key: const Key('home-log-out'),
            label: loggingOut ? 'Logging out…' : 'Log out',
            onTap: loggingOut ? null : onLogOut,
          ),
        ] else ...[
          Text(
            'Not signed in',
            key: const Key('home-signed-out-status'),
            textAlign: TextAlign.left,
            style: uiTextStyle(size: 14, color: colors.muted),
          ),
          const SizedBox(height: 12),
          _HomeLinkRow(
            key: const Key('home-sign-in'),
            label: 'Sign in',
            onTap: onSignIn,
          ),
        ],
        if (error != null) ...[const SizedBox(height: 12), DsErrorBox(error!)],
      ],
    );
  }
}

class _HomeLinkRow extends StatelessWidget {
  const _HomeLinkRow({
    super.key,
    required this.label,
    this.detail,
    required this.onTap,
  });

  final String label;
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final enabled = onTap != null;

    return DsHoverRow(
      onTap: () => onTap?.call(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      hoverOpacity: enabled ? 1 : 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style:
                uiTextStyle(
                  size: 13,
                  weight: 600,
                  color: enabled ? colors.link : colors.muted,
                ).copyWith(
                  decoration: enabled ? TextDecoration.underline : null,
                  decorationColor: enabled ? colors.link : null,
                ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
              style: uiTextStyle(size: 11, color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyCardMessage extends StatelessWidget {
  const _EmptyCardMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      textAlign: TextAlign.left,
      style: uiTextStyle(size: 13, color: context.ds.muted),
    );
  }
}
