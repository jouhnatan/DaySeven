/// The interface for "Run updates".
///
/// The whole flow is one menu item: check the feed, and then either say the
/// app is current, or offer the newer build and install it. There is no
/// prompting at launch — updating happens when somebody asks for it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/platform/app_update.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// Checks for a newer release and, if there is one, offers it.
///
/// The two quiet outcomes — already current, or the check failed — are
/// snackbars rather than dialogs. They are answers to a question the person
/// just asked, so they need to be visible, but neither is worth a modal.
Future<void> runUpdateCheck(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final controller = ref.read(appUpdateProvider.notifier);

  await controller.check();
  if (!context.mounted) return;

  switch (ref.read(appUpdateProvider)) {
    case UpdateAvailable(:final release, :final mandatory):
      await showUpdateDialog(context, release: release, mandatory: mandatory);
    case UpdateCheckFailed(:final message):
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    case _:
      messenger?.showSnackBar(
        const SnackBar(content: Text('DaySeven is up to date.')),
      );
  }
}

/// Offers the update described by [release].
///
/// A mandatory update still has a way out — refusing to let someone close a
/// dialog in an app they are trying to use would be worse than running an old
/// build — but it is worded as expected rather than optional.
Future<void> showUpdateDialog(
  BuildContext context, {
  required AppRelease release,
  required bool mandatory,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (context) => _UpdateDialog(release: release, mandatory: mandatory),
  );
}

class _UpdateDialog extends ConsumerWidget {
  const _UpdateDialog({required this.release, required this.mandatory});

  final AppRelease release;
  final bool mandatory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final state = ref.watch(appUpdateProvider);
    final controller = ref.read(appUpdateProvider.notifier);

    // Downloading and installing are the same moment to the person watching:
    // the app is busy and must not be closed out from under itself.
    final busy = state is DownloadingUpdate || state is InstallingUpdate;

    return DsDialog(
      title: Text(
        'DaySeven ${release.version.name} is available',
        style: uiTextStyle(size: 14, color: colors.text),
      ),
      actions: [
        if (!busy && !mandatory)
          DsDialogAction(
            label: 'Later',
            tone: DsDialogActionTone.muted,
            onPressed: () => Navigator.of(context).pop(),
          ),
        DsDialogAction(
          label: _actionLabel(state),
          onPressed: busy ? null : () => _act(context, controller, state),
        ),
      ],
      children: [
        Text(_body(state), style: uiTextStyle(size: 13, color: colors.text)),
        if (release.releaseNotes case final notes?
            when notes.trim().isNotEmpty && !busy) ...[
          const SizedBox(height: 8),
          Text(notes.trim(), style: uiTextStyle(size: 12, color: colors.muted)),
        ],
        if (state is DownloadingUpdate) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: state.fraction,
            backgroundColor: colors.border,
          ),
        ],
      ],
    );
  }

  String _actionLabel(AppUpdateState state) => switch (state) {
    DownloadingUpdate() => 'Downloading…',
    InstallingUpdate() => 'Installing…',
    // Every failure falls back to the same offer: fetch it by hand.
    UpdateFailed() => 'Download',
    _ => 'Update now',
  };

  String _body(AppUpdateState state) => switch (state) {
    UpdateFailed(:final message) => message,
    InstallingUpdate() => 'DaySeven will close and reopen on the new version.',
    DownloadingUpdate() => 'Downloading the update…',
    _ =>
      mandatory
          ? 'This update is required to keep working with shared knowledge '
                'bases.'
          : 'DaySeven can install this now and reopen itself.',
  };

  Future<void> _act(
    BuildContext context,
    AppUpdateController controller,
    AppUpdateState state,
  ) async {
    // A failure to install in place ends at the published link rather than
    // trying the same thing again.
    if (state is UpdateFailed) {
      await openExternally(release.installUrl ?? release.downloadUrl);
      if (context.mounted) Navigator.of(context).pop();
      return;
    }

    // On success this never returns: the process exits so its own files can be
    // replaced.
    await controller.download(release);
  }
}
