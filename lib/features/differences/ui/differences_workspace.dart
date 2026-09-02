/// The Knowledge Base-wide Differences workspace.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/shared/ui/document_preview.dart';
import 'package:dayseven/features/differences/ui/review_edits_screen.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/theme.dart';

enum DifferencesSort { recent, document, collaborator }

class DifferencesWorkspace extends ConsumerStatefulWidget {
  const DifferencesWorkspace({super.key});

  @override
  ConsumerState<DifferencesWorkspace> createState() =>
      _DifferencesWorkspaceState();
}

class _DifferencesWorkspaceState extends ConsumerState<DifferencesWorkspace> {
  DifferencesSort _sort = DifferencesSort.recent;
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final state = ref.watch(differencesStateProvider);
    final proposals = _visible(state.proposals);

    return DsPane(
      key: const Key('differences-workspace'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 12, 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Differences',
                  style: uiTextStyle(size: 18, weight: 600, color: colors.text),
                ),
                if (state.pendingCount > 0)
                  _CountPill(count: state.pendingCount),
                SizedBox(
                  width: 230,
                  height: 36,
                  child: TextField(
                    key: const Key('differences-filter'),
                    onChanged: (value) => setState(() => _filter = value),
                    decoration: const InputDecoration(
                      hintText: 'Document or collaborator',
                      prefixIcon: Icon(Icons.search, size: 17),
                      isDense: true,
                    ),
                  ),
                ),
                DropdownButton<DifferencesSort>(
                  value: _sort,
                  onChanged: (value) {
                    if (value != null) setState(() => _sort = value);
                  },
                  items: const [
                    DropdownMenuItem(
                      value: DifferencesSort.recent,
                      child: Text('Most recent'),
                    ),
                    DropdownMenuItem(
                      value: DifferencesSort.document,
                      child: Text('Document'),
                    ),
                    DropdownMenuItem(
                      value: DifferencesSort.collaborator,
                      child: Text('Collaborator'),
                    ),
                  ],
                ),
                Tooltip(
                  message: 'Refresh pending edits',
                  child: IconButton(
                    key: const Key('differences-refresh'),
                    onPressed: state.isRefreshing
                        ? null
                        : () => ref
                              .read(differencesControllerProvider.notifier)
                              .refresh(showLoading: true),
                    icon: const Icon(Icons.refresh, size: 19),
                  ),
                ),
                _RealtimeHealth(health: state.realtimeHealth),
              ],
            ),
          ),
          Divider(height: 1, color: colors.border),
          Expanded(child: _body(state, proposals)),
        ],
      ),
    );
  }

  Widget _body(DifferencesState state, List<ChangeSet> proposals) {
    if (state.status == DifferencesLoadStatus.loading &&
        state.proposals.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if ((state.status == DifferencesLoadStatus.error ||
            state.status == DifferencesLoadStatus.offline) &&
        state.proposals.isEmpty) {
      return _DifferencesMessage(
        title: state.status == DifferencesLoadStatus.offline
            ? 'Differences is offline'
            : 'Differences could not load',
        detail: state.errorMessage,
        retry: () => ref
            .read(differencesControllerProvider.notifier)
            .refresh(showLoading: true),
      );
    }
    if (state.status == DifferencesLoadStatus.inactive) {
      return const _DifferencesMessage(
        title: 'Open a shared Knowledge Base',
        detail: 'Pending reviewed edits appear here after you sign in.',
      );
    }
    if (proposals.isEmpty) {
      return _DifferencesMessage(
        title: _filter.trim().isEmpty
            ? 'No edits are waiting for review'
            : 'No pending edits match this filter',
        detail: _filter.trim().isEmpty
            ? 'Realtime and focus refresh will keep checking Postgres.'
            : 'Try a document title or @username.',
      );
    }

    return Column(
      children: [
        if (state.status == DifferencesLoadStatus.error ||
            state.status == DifferencesLoadStatus.offline)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: DsErrorBox(
              state.errorMessage ?? 'The last refresh did not complete.',
            ),
          ),
        Expanded(
          child: GridView.builder(
            key: const Key('differences-paper-grid'),
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 278,
              mainAxisExtent: 382,
              crossAxisSpacing: 22,
              mainAxisSpacing: 22,
            ),
            itemCount: proposals.length,
            itemBuilder: (context, index) => ProposalPaperCard(
              key: ValueKey(proposals[index].id),
              proposal: proposals[index],
              onOpen: () => Navigator.of(context).push(
                reviewEditsRoute(
                  proposals: proposals,
                  initialProposalId: proposals[index].id,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<ChangeSet> _visible(List<ChangeSet> source) {
    final query = _filter.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    final visible = source.where((proposal) {
      if (query.isEmpty) return true;
      return proposal.content.title.toLowerCase().contains(query) ||
          (proposal.proposedPath ?? '').toLowerCase().contains(query) ||
          proposal.authorUsername.toLowerCase().contains(query) ||
          proposal.authorDisplayName.toLowerCase().contains(query);
    }).toList();
    switch (_sort) {
      case DifferencesSort.recent:
        visible.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case DifferencesSort.document:
        visible.sort((a, b) => a.content.title.compareTo(b.content.title));
      case DifferencesSort.collaborator:
        visible.sort((a, b) => a.authorUsername.compareTo(b.authorUsername));
    }
    return visible;
  }
}

class ProposalPaperCard extends StatelessWidget {
  const ProposalPaperCard({
    super.key,
    required this.proposal,
    required this.onOpen,
  });

  final ChangeSet proposal;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final operation = switch (proposal.operation) {
      ChangeSetOperation.create => 'Create',
      ChangeSetOperation.update => 'Edit',
      ChangeSetOperation.delete => 'Delete',
    };
    final title = proposal.content.title.isEmpty
        ? proposal.proposedPath ?? 'Document change'
        : proposal.content.title;
    final paper = colors.editorSurface;
    // The band is a recessed strip under the preview rather than a tint mixed
    // out of the text colour, so it stays a surface the palette actually has.
    final band = colors.cardSurface;

    return Semantics(
      button: true,
      label: '$operation proposal for $title by ${proposal.usernameLabel}',
      hint: 'Open Review edits',
      // Flat and bordered. These are tiles on a page, not sheets of paper
      // lifted off it: depth here comes from the edge, never from a shadow.
      child: Material(
        color: paper,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: CF.line),
          borderRadius: BorderRadius.all(DsRadius.island),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('proposal-paper-${proposal.id}'),
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRect(
                  child: IgnorePointer(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Transform.scale(
                        scale: .68,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: 325,
                          child: DsDocumentPreview(
                            document: proposal.content,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                key: Key('proposal-author-band-${proposal.id}'),
                height: 44,
                color: band,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        proposal.usernameLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: uiTextStyle(
                          size: 13,
                          weight: 500,
                          color: colors.text,
                        ),
                      ),
                    ),
                    Text(
                      operation,
                      style: uiTextStyle(size: 11, color: colors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('differences-pending-count'),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: context.ds.pending,
      borderRadius: BorderRadius.all(DsRadius.pill),
    ),
    child: Text(
      '$count pending',
      style: uiTextStyle(size: 11, weight: 600, color: context.ds.text),
    ),
  );
}

class _RealtimeHealth extends StatelessWidget {
  const _RealtimeHealth({required this.health});
  final DifferencesRealtimeHealth health;

  @override
  Widget build(BuildContext context) {
    final label = switch (health) {
      DifferencesRealtimeHealth.inactive => 'Realtime inactive',
      DifferencesRealtimeHealth.connecting => 'Realtime connecting',
      DifferencesRealtimeHealth.connected => 'Realtime connected',
      DifferencesRealtimeHealth.error =>
        'Realtime unavailable; refresh still works',
    };
    // Semantic colours, as a small mark plus its tooltip. `removal` is a wash
    // meant to sit behind text, so a seven-pixel dot of it would say nothing.
    final color = switch (health) {
      DifferencesRealtimeHealth.connected => context.ds.success,
      DifferencesRealtimeHealth.error => context.ds.danger,
      _ => context.ds.muted,
    };
    return Tooltip(
      message: label,
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _DifferencesMessage extends StatelessWidget {
  const _DifferencesMessage({required this.title, this.detail, this.retry});
  final String title;
  final String? detail;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: uiTextStyle(size: 15, weight: 600, color: context.ds.text),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: uiTextStyle(size: 12, color: context.ds.muted),
              ),
            ],
            if (retry != null) ...[
              const SizedBox(height: 14),
              DsLabelButton(label: 'Try again', onPressed: retry),
            ],
          ],
        ),
      ),
    ),
  );
}
