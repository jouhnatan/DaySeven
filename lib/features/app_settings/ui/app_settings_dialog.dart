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

/// The sibling regions of App settings, in the order the rail lists them.
enum AppSettingsSection {
  general('General'),
  appearance('Appearance'),
  updates('Updates'),
  knowledgeBase('Knowledge Base'),
  about('About'),
  developer('Developer');

  const AppSettingsSection(this.label);

  /// Named as the user would name it, not as the system does.
  final String label;
}

Future<void> showAppSettingsDialog(
  BuildContext context, {
  AppSettingsDeveloperOptionsBuilder? developerOptions,
  Widget? knowledgeBasePanel,
  AppSettingsSection initialSection = AppSettingsSection.general,
}) => showDialog<void>(
  context: context,
  builder: (context) => Consumer(
    builder: (context, ref, _) => AppSettingsDialog(
      developerOptions: developerOptions?.call(ref),
      knowledgeBasePanel: knowledgeBasePanel,
      initialSection: initialSection,
    ),
  ),
);

class AppSettingsDialog extends ConsumerStatefulWidget {
  const AppSettingsDialog({
    super.key,
    this.developerOptions,
    this.knowledgeBasePanel,
    this.initialSection = AppSettingsSection.general,
  });

  final AppSettingsDeveloperOptions? developerOptions;

  /// The Knowledge Base section's body, supplied by the composition root.
  /// It belongs to another feature, and features do not import each other.
  final Widget? knowledgeBasePanel;

  final AppSettingsSection initialSection;

  @override
  ConsumerState<AppSettingsDialog> createState() => _AppSettingsDialogState();
}

class _AppSettingsDialogState extends ConsumerState<AppSettingsDialog> {
  final Set<String> _workingSettings = {};
  String? _settingsError;
  late AppSettingsSection _section = widget.initialSection;
  bool _autoUpdate = true;
  String _channel = 'Stable';

  /// A section is listed only when it has something to say. Developer options
  /// are absent in an ordinary build, and there is no Knowledge Base section
  /// until one is open.
  List<AppSettingsSection> get _sections => [
    AppSettingsSection.general,
    AppSettingsSection.appearance,
    AppSettingsSection.updates,
    if (widget.knowledgeBasePanel != null) AppSettingsSection.knowledgeBase,
    AppSettingsSection.about,
    if (widget.developerOptions != null) AppSettingsSection.developer,
  ];

  @override
  void initState() {
    super.initState();
    // Deep-linking to a section the build does not have would leave the rail
    // with nothing selected.
    if (!_sections.contains(_section)) _section = AppSettingsSection.general;
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
    final sections = _sections;

    return Dialog(
      key: const Key('app-settings-dialog'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 44),
      child: ConstrainedBox(
        // A fixed size, so that moving between sections does not resize the
        // window around the person reading it. Settings is a quiet surface a
        // person reads a line at a time; it does not need the room a document
        // does, and a smaller one is easier to take in at a glance.
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 470),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _Header(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // With one section there is nowhere to navigate to, and
                      // a rail of one item would be chrome describing itself.
                      if (sections.length > 1) ...[
                        _SectionRail(
                          sections: sections,
                          selected: _section,
                          onSelect: (section) =>
                              setState(() => _section = section),
                        ),
                        const VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: CF.hairline,
                        ),
                      ],
                      Expanded(
                        child: SingleChildScrollView(
                          // Each section starts at its own top rather than
                          // inheriting the last one's scroll position.
                          key: ValueKey(_section),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 4),
                              ...switch (_section) {
                                AppSettingsSection.general => _generalSection(),
                                AppSettingsSection.appearance =>
                                  _appearanceSection(),
                                AppSettingsSection.updates =>
                                  _updatesSection(),
                                AppSettingsSection.knowledgeBase =>
                                  _knowledgeBaseSection(),
                                AppSettingsSection.about => _aboutSection(),
                                AppSettingsSection.developer =>
                                  _developerSection(),
                              },
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
                    ],
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

  List<Widget> _generalSection() => [
    const _SectionHeading('General'),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        'DaySeven is a workspace for building worlds. '
        'Choose a section on the left to adjust its settings.',
        style: uiTextStyle(size: 13, color: CF.muted),
      ),
    ),
  ];

  List<Widget> _appearanceSection() => [
    const _SectionHeading('Appearance'),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DsSettingRow(
        label: 'Gradient background',
        helper: 'Soft pools behind Home and other views',
        trailing: Switch(
          value: true,
          onChanged: (_) {},
        ),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DsSettingRow(
        label: 'Window chrome',
        helper: 'Uses the system theme for the title bar',
        trailing: Switch(value: true, onChanged: null),
      ),
    ),
  ];

  List<Widget> _updatesSection() {
    final state = ref.watch(appUpdateProvider);
    final enabled = ref.read(appUpdateProvider.notifier).enabled;

    return [
      const _SectionHeading('Updates'),
      _UpdateStatusBlock(state: state, enabled: enabled),
      if (state case UpdateCheckFailed(:final message))
        _Alert(message: message),
      if (state case UpdateFailed(:final message, :final release))
        _Alert(message: message, release: release),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: DsSettingRow(
          label: 'Install updates automatically',
          helper: 'Applies on next launch',
          trailing: Switch(
            value: _autoUpdate,
            onChanged: (value) => setState(() => _autoUpdate = value),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: CF.hairline)),
          ),
          padding: const EdgeInsets.only(top: 12),
          child: DsSettingRow(
            label: 'Channel',
            helper: 'Beta builds land about a week early',
            trailing: DsSegmented<String>(
              value: _channel,
              onPick: (value) => setState(() => _channel = value),
              options: const [
                DsSegmentedOption(
                  value: 'Stable',
                  semanticLabel: 'Stable',
                  child: Text('Stable'),
                ),
                DsSegmentedOption(
                  value: 'Beta',
                  semanticLabel: 'Beta',
                  child: Text('Beta'),
                ),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Row(
          children: [
            GestureDetector(
              onTap: () {},
              child: Text(
                "What's new in ${ref.watch(currentVersionProvider).valueOrNull?.name ?? '1.3.7'}",
                style: uiTextStyle(
                  size: 13,
                  color: CF.slate,
                  weight: 500,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 1,
          color: CF.hairline,
        ),
      ),
    ];
  }

  List<Widget> _aboutSection() => [
    const _SectionHeading('About'),
    _VersionRow(),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        'A world-building knowledge base editor. '
        'Updates are published from the release feed and installed on next launch.',
        style: uiTextStyle(size: 13, color: CF.muted),
      ),
    ),
  ];

  List<Widget> _knowledgeBaseSection() => [
    const _SectionHeading('Knowledge Base'),
    Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: widget.knowledgeBasePanel ?? const SizedBox.shrink(),
    ),
  ];

  List<Widget> _developerSection() {
    final developer = widget.developerOptions;
    if (developer == null) return const [];

    return [
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
        onChanged: (value) =>
            _changeSetting('crdt', () => developer.setCrdtCollaboration(value)),
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
      if (developer.policyDetail case final detail?) ...[
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DsStatusBlock(
            key: const Key('app-settings-policy-signing'),
            icon: Icons.key_outlined,
            tone: developer.republishPolicy == null
                ? DsTone.success
                : DsTone.warning,
            headline: developer.republishPolicy == null
                ? 'Policy signing ready'
                : 'Policy signing needs attention',
            detail: detail,
            trailing: developer.republishPolicy == null
                ? null
                : DsLabelButton(
                    key: const Key('app-settings-republish-policy'),
                    label: _workingSettings.contains('policy')
                        ? 'Republishing…'
                        : 'Republish',
                    height: DsSize.control,
                    onPressed: _workingSettings.contains('policy')
                        ? null
                        : () => _changeSetting(
                            'policy',
                            developer.republishPolicy!,
                          ),
                  ),
          ),
        ),
      ],
      if (developer.refusalCount > 0)
        _Alert(
          title: 'An incoming update was refused',
          message:
              '${developer.refusalCount} update(s) were '
              'kept out of this workspace. '
              '${developer.refusalDetail ?? 'The signed policy did not allow them.'}',
        ),
    ];
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

/// Says when the update check last answered, in the words a person would use.
///
/// "Up to date" on its own is a claim with no shelf life. Naming the moment it
/// was established is what lets somebody tell a fresh answer from a stale one.
@visibleForTesting
String describeLastChecked(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Not checked yet';

  final today = now ?? DateTime.now();
  final day = DateTime(at.year, at.month, at.day);
  final difference = DateTime(
    today.year,
    today.month,
    today.day,
  ).difference(day).inDays;

  final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  final meridiem = at.hour < 12 ? 'AM' : 'PM';
  final clock = '$hour:$minute $meridiem';

  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return switch (difference) {
    0 => 'Checked today at $clock',
    1 => 'Checked yesterday at $clock',
    _ => 'Checked ${at.day} ${months[at.month - 1]} at $clock',
  };
}

/// The rail: the sibling regions of App settings, and which one you are in.
///
/// The selected item is a solid block of the accent rather than a bolder
/// label, because position is shown by fill. It is one of the two things fern
/// is spent on in this dialog; the other is the update button.
class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<AppSettingsSection> sections;
  final AppSettingsSection selected;
  final ValueChanged<AppSettingsSection> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    width: 172,
    color: CF.inset,
    padding: const EdgeInsets.all(DsSpace.s),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpace.xxs),
            child: DsHoverRow(
              key: Key('app-settings-section-${section.name}'),
              selected: section == selected,
              semanticLabel: section.label,
              onTap: () => onSelect(section),
              padding: const EdgeInsets.symmetric(horizontal: 11),
              child: SizedBox(
                height: 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    section.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DsType.label(
                      color: section == selected ? CF.onFern : CF.muted,
                      weight: section == selected ? 500 : 400,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    // A boolean setting is a toggle on the right of its row, and the theme
    // already states how one looks; restating it here is how the two drift.
    child: DsSettingRow(
      label: title,
      helper: subtitle,
      trailing: Switch(value: value, onChanged: working ? null : onChanged),
    ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DsStatusBlock(
        key: const Key('app-settings-collaboration-state'),
        icon: switch (options.collaborationHealth) {
          AppSettingsCollaborationHealth.connected => Icons.cloud_done_outlined,
          AppSettingsCollaborationHealth.connecting => Icons.sync,
          AppSettingsCollaborationHealth.degraded ||
          AppSettingsCollaborationHealth.unavailable =>
            Icons.cloud_off_outlined,
          AppSettingsCollaborationHealth.off => Icons.hub_outlined,
        },
        tone: switch (options.collaborationHealth) {
          AppSettingsCollaborationHealth.connected => DsTone.success,
          AppSettingsCollaborationHealth.degraded => DsTone.warning,
          AppSettingsCollaborationHealth.unavailable => DsTone.danger,
          _ => DsTone.neutral,
        },
        headline: title,
        detail: detail,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    // Paper, with a rule under it. A filled bar would be a tinted block put
    // behind a title to group it, which is the thing hairlines exist to avoid.
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CF.hairline)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Settings',
                style: uiHeaderTextStyle(size: 16, height: 22 / 16),
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
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
    child: Text(
      label,
      // Solway labels the region. It is not spending the accent to do it:
      // fern is reserved for where you are and for what commits.
      style: uiHeaderTextStyle(size: 16, height: 22 / 16),
    ),
  );
}

class _VersionRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(currentVersionProvider);

    // Label left, value right — and the value is tabular, because it is a
    // number somebody reads off against the one a release note names.
    return Padding(
      key: const Key('app-settings-version'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DsSettingRow(
        first: true,
        label: 'DaySeven',
        helper: switch (version) {
          AsyncData(:final value) => 'Build ${value.build}',
          AsyncError() => 'Version unavailable',
          _ => 'Reading…',
        },
        trailing: Text(switch (version) {
          AsyncData(:final value) => value.name,
          _ => '—',
        }, style: DsType.bodyStrong(tabular: true)),
      ),
    );
  }
}

class _UpdateStatusBlock extends ConsumerWidget {
  const _UpdateStatusBlock({required this.state, required this.enabled});

  final AppUpdateState state;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!enabled) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: DsStatusBlock(
          icon: Icons.cloud_off_outlined,
          headline: 'No server configured',
          detail:
              'Updates are published to Supabase, and this build has no '
              'connection details for it.',
        ),
      );
    }

    final controller = ref.read(appUpdateProvider.notifier);
    final busy = state is DownloadingUpdate || state is InstallingUpdate;
    final isCheckAction = state is! UpdateAvailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: DsStatusBlock(
            key: const Key('app-settings-update-status'),
            icon: switch (state) {
              UpdateAvailable() => Icons.arrow_circle_down_outlined,
              UpdateCheckFailed() || UpdateFailed() => Icons.error_outline,
              CheckingForUpdate() => Icons.sync,
              _ => Icons.check_circle_outline,
            },
            tone: switch (state) {
              UpdateAvailable() => DsTone.warning,
              UpdateCheckFailed() || UpdateFailed() => DsTone.danger,
              CheckingForUpdate() => DsTone.neutral,
              _ => DsTone.success,
            },
            headline: switch (state) {
              UpdateAvailable(:final release) =>
                'Version ${release.version.name}',
              DownloadingUpdate() => 'Downloading',
              InstallingUpdate() => 'Installing',
              _ => 'Up to date',
            },
            detail: switch (state) {
              UpdateAvailable(:final release) =>
                'Build ${release.version.build}',
              CheckingForUpdate() => 'Checking…',
              DownloadingUpdate(:final release) =>
                '${(release.sizeBytes / 1048576).toStringAsFixed(1)} MB',
              UpToDate(:final checkedAt) => describeLastChecked(checkedAt),
              _ => 'Nothing newer published',
            },
            trailing: isCheckAction
                ? DsButton(
                    key: const Key('app-settings-run-updates'),
                    height: DsSize.smallControl,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    onPressed: busy
                        ? null
                        : () => switch (state) {
                            UpdateAvailable(:final release) =>
                              controller.download(release),
                            _ => controller.check(),
                          },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sync, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          switch (state) {
                            CheckingForUpdate() => 'Checking…',
                            DownloadingUpdate() => 'Downloading…',
                            InstallingUpdate() => 'Installing…',
                            _ => 'Check now',
                          },
                          style: uiTextStyle(size: 13, weight: 500),
                        ),
                      ],
                    ),
                  )
                : DsLabelButton(
                    key: const Key('app-settings-run-updates'),
                    label: switch (state) {
                      DownloadingUpdate() => 'Downloading…',
                      InstallingUpdate() => 'Installing…',
                      UpdateAvailable(:final release) =>
                        'Install ${release.version.name}',
                      _ => 'Check now',
                    },
                    height: DsSize.control,
                    horizontalPadding: 17,
                    variant: DsButtonVariant.primary,
                    onPressed: busy
                        ? null
                        : () => controller.download(
                            (state as UpdateAvailable).release,
                          ),
                  ),
          ),
        ),
        if (state case DownloadingUpdate(:final fraction))
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
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
      border: Border(top: BorderSide(color: CF.hairline)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          DsLabelButton(
            label: 'Done',
            variant: DsButtonVariant.primary,
            height: DsSize.control,
            horizontalPadding: 17,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ),
  );
}
