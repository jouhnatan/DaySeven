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

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/platform/app_update.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/theme.dart';

typedef AppSettingsDeveloperOptionsBuilder =
    AppSettingsDeveloperOptions Function(WidgetRef ref);
typedef AppSettingsPanelBuilder = Widget Function(WidgetRef ref);

class AppSettingsDeveloperOptions {
  const AppSettingsDeveloperOptions({
    required this.showWorkspaceMetadata,
    required this.setShowWorkspaceMetadata,
  });

  final bool showWorkspaceMetadata;
  final Future<void> Function(bool enabled) setShowWorkspaceMetadata;
}

/// The sibling regions of App settings, in the order the switcher lists them.
enum AppSettingsSection {
  updates('Updates'),
  knowledgeBase('Knowledge Base'),
  developer('Developer');

  const AppSettingsSection(this.label);

  /// Named as the user would name it, not as the system does.
  final String label;
}

Future<void> showAppSettingsDialog(
  BuildContext context, {
  AppSettingsDeveloperOptionsBuilder? developerOptions,
  Widget? knowledgeBasePanel,
  AppSettingsPanelBuilder? knowledgeBasePanelBuilder,
  AppSettingsSection initialSection = AppSettingsSection.updates,
}) => showDialog<void>(
  context: context,
  builder: (context) => Consumer(
    builder: (context, ref, _) => AppSettingsDialog(
      developerOptions: developerOptions?.call(ref),
      knowledgeBasePanel:
          knowledgeBasePanelBuilder?.call(ref) ?? knowledgeBasePanel,
      initialSection: initialSection,
    ),
  ),
);

class AppSettingsDialog extends ConsumerStatefulWidget {
  const AppSettingsDialog({
    super.key,
    this.developerOptions,
    this.knowledgeBasePanel,
    this.initialSection = AppSettingsSection.updates,
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

  /// A section is listed only when it has something to say. Developer options
  /// are absent in an ordinary build, and there is no Knowledge Base section
  /// until one is open.
  List<AppSettingsSection> get _sections => [
    AppSettingsSection.updates,
    if (widget.knowledgeBasePanel != null) AppSettingsSection.knowledgeBase,
    if (widget.developerOptions != null) AppSettingsSection.developer,
  ];

  @override
  void initState() {
    super.initState();
    // Deep-linking to a section the build does not have would leave the
    // switcher with nothing selected.
    if (!_sections.contains(_section)) _section = AppSettingsSection.updates;
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
                _Header(
                  // With one section there is nowhere to navigate to, and a
                  // switcher of one cell would be chrome describing itself.
                  switcher: sections.length > 1
                      ? _SectionSwitcher(
                          sections: sections,
                          selected: _section,
                          onSelect: (section) =>
                              setState(() => _section = section),
                        )
                      : null,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    // Each section starts at its own top rather than
                    // inheriting the last one's scroll position.
                    key: ValueKey(_section),
                    padding: const EdgeInsets.symmetric(horizontal: DsSpace.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // The switcher above already names the section, so the
                        // body opens on its first setting rather than repeating
                        // the heading underneath the cell it was chosen from.
                        const SizedBox(height: 18),
                        ...switch (_section) {
                          AppSettingsSection.updates => _updatesSection(),
                          AppSettingsSection.knowledgeBase =>
                            _knowledgeBaseSection(),
                          AppSettingsSection.developer => _developerSection(),
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
                const _Footer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _updatesSection() {
    final state = ref.watch(appUpdateProvider);
    final enabled = ref.read(appUpdateProvider.notifier).enabled;

    return [
      _UpdateStatusBlock(state: state, enabled: enabled),
      if (state case UpdateCheckFailed(:final message))
        _Alert(message: message),
      if (state case UpdateFailed(:final message, :final release))
        _Alert(message: message, release: release),
    ];
  }

  List<Widget> _knowledgeBaseSection() => [
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: widget.knowledgeBasePanel ?? const SizedBox.shrink(),
    ),
  ];

  List<Widget> _developerSection() {
    final developer = widget.developerOptions;
    if (developer == null) return const [];

    return [
      _DeveloperToggleRow(
        first: true,
        key: const Key('app-settings-metadata-toggle'),
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
      if (mounted) setState(() => _settingsError = describeError(error));
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

/// The switcher: the sibling regions of App settings, and which one you are
/// in.
///
/// A segmented strip centred under the title, so the regions read as one row
/// of peers rather than a column down the side. Selection is the strip's own
/// raised cell rather than fern: the accent is spent on what commits.
class _SectionSwitcher extends StatelessWidget {
  const _SectionSwitcher({
    required this.sections,
    required this.selected,
    required this.onSelect,
  });

  final List<AppSettingsSection> sections;
  final AppSettingsSection selected;
  final ValueChanged<AppSettingsSection> onSelect;

  @override
  Widget build(BuildContext context) => DsSegmented<AppSettingsSection>(
    value: selected,
    onPick: onSelect,
    options: [
      for (final section in sections)
        DsSegmentedOption(
          value: section,
          semanticLabel: section.label,
          child: KeyedSubtree(
            key: Key('app-settings-section-${section.name}'),
            child: Text(
              section.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DsType.label(weight: section == selected ? 500 : 400),
            ),
          ),
        ),
    ],
  );
}

class _DeveloperToggleRow extends StatelessWidget {
  const _DeveloperToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.working,
    required this.onChanged,
    this.first = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool working;
  final ValueChanged<bool> onChanged;
  final bool first;

  @override
  Widget build(BuildContext context) => DsSettingRow(
    first: first,
    label: title,
    helper: subtitle,
    trailing: Switch(value: value, onChanged: working ? null : onChanged),
  );
}

class _Header extends StatelessWidget {
  const _Header({this.switcher});

  /// The section switcher, centred on its own line under the title. It is
  /// absent when the build has only one section to show.
  final Widget? switcher;

  @override
  Widget build(BuildContext context) {
    // Paper, with a rule under it. A filled bar would be a tinted block put
    // behind a title to group it, which is the thing hairlines exist to avoid.
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: CF.hairline)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 12, switcher == null ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
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
            if (switcher case final switcher?) ...[
              const SizedBox(height: 10),
              // Centred under the title: the regions are peers, so no one of
              // them sits closer to the edge than the rest.
              Center(child: switcher),
            ],
          ],
        ),
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
      return const DsStatusBlock(
        icon: Icons.cloud_off_outlined,
        headline: 'No server configured',
        detail:
            'Updates are published to Supabase, and this build has no '
            'connection details for it.',
      );
    }

    final controller = ref.read(appUpdateProvider.notifier);
    final busy = state is DownloadingUpdate || state is InstallingUpdate;
    final isCheckAction = state is! UpdateAvailable;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DsStatusBlock(
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
            UpdateAvailable(:final release) => 'Build ${release.version.build}',
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
                      Text(switch (state) {
                        CheckingForUpdate() => 'Checking…',
                        DownloadingUpdate() => 'Downloading…',
                        InstallingUpdate() => 'Installing…',
                        _ => 'Check now',
                      }, style: uiTextStyle(size: 13, weight: 500)),
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
        if (state case DownloadingUpdate(:final fraction))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Container(
              height: 16,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: CF.paper,
                border: Border.all(color: CF.line),
                borderRadius: const BorderRadius.all(DsRadius.row),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.all(DsRadius.none),
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
      padding: const EdgeInsets.only(top: 22, bottom: 12),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title ??
                          (release == null
                              ? "Couldn't check for updates"
                              : "Couldn't install that update"),
                      style: DsType.bodyStrong(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DsCopyErrorButton(message: message),
                ],
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
