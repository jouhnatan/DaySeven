/// App settings: what version this is, and whether it is the current one.
///
/// The dialog exists because "Run updates" on its own asked people to act
/// without telling them anything first. Here the answer comes before the
/// button: the hero line says whether this build is current, and the update
/// control sits underneath it.
///
/// It is built from the application's own tokens. It used to carry a second,
/// private design system — a separate palette, three typefaces of its own, and
/// a film grain — because the application theme was not something a settings
/// surface wanted to look like. That is no longer true, so the exception is
/// gone rather than maintained.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/platform/app_update.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

typedef AppSettingsDeveloperOptionsBuilder =
    AppSettingsDeveloperOptions Function(WidgetRef ref);

enum AppSettingsCollaborationHealth {
  off,
  connecting,
  connected,
  degraded,
  unavailable,
}

class AppSettingsDeveloperOptions {
  const AppSettingsDeveloperOptions({
    required this.showWorkspaceMetadata,
    required this.crdtCollaboration,
    required this.setShowWorkspaceMetadata,
    required this.setCrdtCollaboration,
    required this.collaborationHealth,
    this.collaborationDetail,
    this.cursor = 0,
    this.pendingLocalPush = false,
    this.queuedInbound = 0,
    this.refusalCount = 0,
    this.refusalDetail,
    this.policyDetail,
    this.republishPolicy,
  });

  final bool showWorkspaceMetadata;
  final bool crdtCollaboration;
  final Future<void> Function(bool enabled) setShowWorkspaceMetadata;
  final Future<void> Function(bool enabled) setCrdtCollaboration;
  final AppSettingsCollaborationHealth collaborationHealth;
  final String? collaborationDetail;
  final int cursor;
  final bool pendingLocalPush;
  final int queuedInbound;
  final int refusalCount;
  final String? refusalDetail;
  final String? policyDetail;
  final Future<void> Function()? republishPolicy;
}

Future<void> showAppSettingsDialog(
  BuildContext context, {
  AppSettingsDeveloperOptionsBuilder? developerOptions,
}) => showDialog<void>(
  context: context,
  builder: (context) => Consumer(
    builder: (context, ref, _) =>
        AppSettingsDialog(developerOptions: developerOptions?.call(ref)),
  ),
);

class AppSettingsDialog extends ConsumerStatefulWidget {
  const AppSettingsDialog({super.key, this.developerOptions});

  final AppSettingsDeveloperOptions? developerOptions;

  @override
  ConsumerState<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends ConsumerState<AppSettingsDialog> {
  final Set<String> _workingSettings = {};
  String? _settingsError;

  @override
  void initState() {
    super.initState();
    // Check on open, so the hero is answering rather than guessing. Without a
    // server there is no feed and nothing to ask; the controller already knows
    // whether there is one, so that is where the question goes.
    if (ref.read(appUpdateProvider.notifier).enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(appUpdateProvider.notifier).check();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateProvider);
    final enabled = ref.read(appUpdateProvider.notifier).enabled;
    final developer = widget.developerOptions;

    return Dialog(
      key: const Key('app-settings-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 44),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: CF.paper,
            borderRadius: BorderRadius.all(DsRadius.island),
            // Flat: the edge carries the depth, and the scrim behind the
            // dialog does the rest.
            border: Border.fromBorderSide(BorderSide(color: CF.line)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.all(DsRadius.island),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 4),
                        const _SectionHeading('Version'),
                        _VersionRow(),
                        const _SectionHeading('Updates'),
                        _UpdateRow(state: state, enabled: enabled),
                        if (state case UpdateCheckFailed(:final message))
                          _Alert(message: message),
                        if (state case UpdateFailed(
                          :final message,
                          :final release,
                        ))
                          _Alert(message: message, release: release),
                        if (developer != null) ...[
                          const _SectionHeading('Developer'),
                          _DeveloperToggleRow(
                            key: const Key('app-settings-crdt-toggle'),
                            icon: Icons.hub_outlined,
                            title: 'CRDT collaboration',
                            subtitle: developer.crdtCollaboration
                                ? 'On for the open Knowledge Base. The reviewed '
                                      'edit path remains available.'
                                : 'Off. Reviewed edits remain authoritative.',
                            value: developer.crdtCollaboration,
                            working: _workingSettings.contains('crdt'),
                            onChanged: (value) => _changeSetting(
                              'crdt',
                              () => developer.setCrdtCollaboration(value),
                            ),
                          ),
                          _DeveloperToggleRow(
                            key: const Key('app-settings-metadata-toggle'),
                            icon: Icons.folder_open_outlined,
                            title: 'Show workspace metadata',
                            subtitle: developer.showWorkspaceMetadata
                                ? 'metadata/ is visible in the tree and search.'
                                : 'metadata/ stays hidden from the writing view.',
                            value: developer.showWorkspaceMetadata,
                            working: _workingSettings.contains('metadata'),
                            onChanged: (value) => _changeSetting(
                              'metadata',
                              () => developer.setShowWorkspaceMetadata(value),
                            ),
                          ),
                          const _SectionHeading('Collaboration'),
                          _CollaborationRow(options: developer),
                          if (developer.policyDetail case final detail?)
                            _Row(
                              key: const Key('app-settings-policy-signing'),
                              plate: const _Plate(
                                Icons.key_outlined,
                                pale: true,
                              ),
                              title: developer.republishPolicy == null
                                  ? 'Policy signing ready'
                                  : 'Policy signing needs attention',
                              subtitle: detail,
                              subtitleIsMeta: false,
                              trailing: developer.republishPolicy == null
                                  ? null
                                  : DsLabelButton(
                                      key: const Key(
                                        'app-settings-republish-policy',
                                      ),
                                      label: _workingSettings.contains('policy')
                                          ? 'Republishing…'
                                          : 'Republish',
                                      height: DsSize.control,
                                      onPressed:
                                          _workingSettings.contains('policy')
                                          ? null
                                          : () => _changeSetting(
                                              'policy',
                                              developer.republishPolicy!,
                                            ),
                                    ),
                            ),
                          if (developer.refusalCount > 0)
                            _Alert(
                              title: 'An incoming update was refused',
                              message:
                                  '${developer.refusalCount} update(s) were '
                                  'kept out of this workspace. '
                                  '${developer.refusalDetail ?? 'The signed policy did not allow them.'}',
                            ),
                        ],
                        if (_settingsError case final message?)
                          _Alert(
                            title: "Couldn't change that setting",
                            message: message,
                          ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
                const _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeSetting(
    String name,
    Future<void> Function() change,
  ) async {
    setState(() {
      _workingSettings.add(name);
      _settingsError = null;
    });
    try {
      await change();
    } on Object catch (error) {
      if (mounted) setState(() => _settingsError = '$error');
    } finally {
      if (mounted) setState(() => _workingSettings.remove(name));
    }
  }
}

class _DeveloperToggleRow extends StatelessWidget {
  const _DeveloperToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.working,
    required this.onChanged,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool working;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Row(
    plate: _Plate(icon, pale: true),
    title: title,
    subtitle: subtitle,
    subtitleIsMeta: false,
    // A boolean setting is a toggle, and the theme already states how one
    // looks; restating it here is how the two drift apart.
    trailing: Switch(value: value, onChanged: working ? null : onChanged),
  );
}

class _CollaborationRow extends StatelessWidget {
  const _CollaborationRow({required this.options});

  final AppSettingsDeveloperOptions options;

  @override
  Widget build(BuildContext context) {
    final title = switch (options.collaborationHealth) {
      AppSettingsCollaborationHealth.off => 'Collaboration is off',
      AppSettingsCollaborationHealth.connecting => 'Connecting',
      AppSettingsCollaborationHealth.connected => 'Connected',
      AppSettingsCollaborationHealth.degraded => 'Connection degraded',
      AppSettingsCollaborationHealth.unavailable => 'Collaboration unavailable',
    };
    final detail =
        options.collaborationDetail ??
        switch (options.collaborationHealth) {
          AppSettingsCollaborationHealth.off =>
            'Enable the developer toggle above to start a session.',
          AppSettingsCollaborationHealth.connecting =>
            'Catching up from the durable update log.',
          AppSettingsCollaborationHealth.connected => [
            'Durable cursor ${options.cursor}',
            if (options.pendingLocalPush) 'local changes waiting to push',
            if (options.queuedInbound > 0)
              '${options.queuedInbound} incoming update(s) queued',
          ].join(' · '),
          AppSettingsCollaborationHealth.degraded =>
            'Files remain saved on this device while sharing recovers.',
          AppSettingsCollaborationHealth.unavailable =>
            'Local editing remains available.',
        };

    return _Row(
      key: const Key('app-settings-collaboration-state'),
      plate: _Plate(switch (options.collaborationHealth) {
        AppSettingsCollaborationHealth.connected => Icons.cloud_done_outlined,
        AppSettingsCollaborationHealth.connecting => Icons.sync,
        AppSettingsCollaborationHealth.degraded ||
        AppSettingsCollaborationHealth.unavailable => Icons.cloud_off_outlined,
        AppSettingsCollaborationHealth.off => Icons.hub_outlined,
      }),
      title: title,
      subtitle: detail,
      subtitleIsMeta: false,
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    // A title bar in cream. It used to be a charcoal block, which was the one
    // piece of dark chrome left in the product.
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CF.bar,
        border: Border(bottom: BorderSide(color: CF.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'App settings',
                style: uiHeaderTextStyle(size: 22, height: 28 / 22),
              ),
            ),
            DsButton(
              variant: DsButtonVariant.quiet,
              semanticLabel: 'Close',
              height: DsSize.smallControl,
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              child: const Tooltip(
                message: 'Close',
                child: SizedBox(
                  width: DsSize.smallControl,
                  child: Icon(Icons.close, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
    child: Text(
      label,
      // Solway labels the region. It is not spending the accent to do it:
      // fern is reserved for where you are and for what commits.
      style: uiHeaderTextStyle(size: 16, height: 22 / 16),
    ),
  );
}

/// A flat row: solid fill, no shadow, no radius games.
class _Row extends StatelessWidget {
  const _Row({
    required this.plate,
    required this.title,
    required this.subtitle,
    this.subtitleIsMeta = true,
    this.trailing,
    super.key,
  });

  final Widget plate;
  final String title;
  final String subtitle;

  /// A short status or version, rather than a sentence. Both are set in the
  /// body face; the design separates them only by grey.
  final bool subtitleIsMeta;

  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: CF.inset,
        borderRadius: BorderRadius.all(DsRadius.menu),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(minHeight: 66),
        child: Row(
          children: [
            plate,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A row title is a value — a version, a state — so it is
                  // set in the sans. Solway labels regions and nothing else.
                  Text(title, style: DsType.bodyStrong(tabular: true)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: DsType.caption(
                      color: subtitleIsMeta ? CF.muted : CF.muted,
                      tabular: subtitleIsMeta,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 14),
              trailing,
            ],
          ],
        ),
      ),
    ),
  );
}

/// A square flat icon plate.
class _Plate extends StatelessWidget {
  const _Plate(this.icon, {this.pale = false});

  final IconData icon;
  final bool pale;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 42,
    height: 42,
    // Decorative, so it takes the decorative colour rather than the accent.
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: pale ? CF.paper : CF.sage,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: pale ? CF.line : CF.sage),
      ),
      child: Center(
        child: Icon(icon, size: 20, color: pale ? CF.muted : CF.onSage),
      ),
    ),
  );
}

class _VersionRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(currentVersionProvider);

    return _Row(
      key: const Key('app-settings-version'),
      plate: const _Plate(Icons.tag, pale: true),
      title: switch (version) {
        AsyncData(:final value) => 'DaySeven ${value.name}',
        _ => 'DaySeven',
      },
      subtitle: switch (version) {
        AsyncData(:final value) => 'Build ${value.build}',
        AsyncError() => 'Version unavailable',
        _ => 'Reading…',
      },
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow({required this.state, required this.enabled});

  final AppUpdateState state;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return _Row(
        plate: const _Plate(Icons.cloud_off, pale: true),
        title: 'No server configured',
        subtitle:
            'Updates are published to Supabase, and this build has no '
            'connection details for it.',
        subtitleIsMeta: false,
      );
    }

    final controller = ref.read(appUpdateProvider.notifier);
    final busy = state is DownloadingUpdate || state is InstallingUpdate;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Row(
          plate: _Plate(switch (state) {
            UpdateAvailable() => Icons.arrow_downward,
            UpdateCheckFailed() || UpdateFailed() => Icons.error_outline,
            _ => Icons.refresh,
          }),
          title: switch (state) {
            UpdateAvailable(:final release) =>
              'Version ${release.version.name}',
            DownloadingUpdate() => 'Downloading',
            InstallingUpdate() => 'Installing',
            _ => 'Up to date',
          },
          subtitle: switch (state) {
            UpdateAvailable(:final release) => 'Build ${release.version.build}',
            CheckingForUpdate() => 'Checking…',
            DownloadingUpdate(:final release) =>
              '${(release.sizeBytes / 1048576).toStringAsFixed(1)} MB',
            _ => 'Nothing newer published',
          },
          // The action that commits, so it is the one fern-filled control on
          // this surface. Its label names what will happen.
          trailing: DsLabelButton(
            key: const Key('app-settings-run-updates'),
            label: switch (state) {
              DownloadingUpdate() => 'Downloading…',
              InstallingUpdate() => 'Installing…',
              UpdateAvailable(:final release) =>
                'Install ${release.version.name}',
              _ => 'Run updates',
            },
            variant: DsButtonVariant.primary,
            height: DsSize.control,
            horizontalPadding: 17,
            onPressed: busy
                ? null
                : () => switch (state) {
                    UpdateAvailable(:final release) => controller.download(
                      release,
                    ),
                    // Already current, or the last check failed: ask again.
                    _ => controller.check(),
                  },
          ),
        ),
        if (state case DownloadingUpdate(:final fraction))
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            // Linear, framed, and filled with fern. Progress is one of the
            // few places a large fern surface is earned: it is the action the
            // person asked for, still running.
            child: Container(
              height: 16,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: CF.paper,
                border: Border.all(color: CF.line),
                borderRadius: const BorderRadius.all(DsRadius.row),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(3)),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 10,
                  backgroundColor: CF.inset,
                  color: CF.fern,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The banner the system uses for a failure: a wash, a hairline in the
/// matching semantic colour, and ink text. A full-width banner is the one
/// place a semantic colour is allowed to fill a block.
class _Alert extends StatelessWidget {
  const _Alert({required this.message, this.release, this.title});

  final String message;
  final String? title;

  /// Present when an install failed rather than a check, so there is something
  /// to fall back to fetching by hand.
  final AppRelease? release;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 22, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: CF.dangerWash,
          borderRadius: const BorderRadius.all(DsRadius.menu),
          border: Border.all(color: CF.danger.withValues(alpha: 0.30)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title ??
                    (release == null
                        ? "Couldn't check for updates"
                        : "Couldn't install that update"),
                style: DsType.bodyStrong(),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: CF.danger.withValues(alpha: 0.30)),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(
                    message,
                    key: const Key('app-settings-alert'),
                    style: DsType.caption(color: CF.ink),
                  ),
                ),
              ),
              if (release case final release?) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: DsLabelButton(
                    label: 'Download',
                    height: DsSize.control,
                    onPressed: () => openExternally(
                      release.installUrl ?? release.downloadUrl,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: CF.bar,
      border: Border(top: BorderSide(color: CF.hairline)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Dismissal, not a commitment: the action that actually does
          // something on this surface is the update button, and there is only
          // ever one of those.
          DsLabelButton(
            label: 'Done',
            height: DsSize.control,
            horizontalPadding: 17,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}
