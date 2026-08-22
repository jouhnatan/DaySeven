/// Knowledge Base-wide inbox for reviewed collaboration proposals.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/review/data/proposals.dart';
import 'package:dayseven/features/review/ui/diff_screen.dart';
import 'package:dayseven/shared/blocks/revision.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

Route<void> reviewInboxRoute() => MaterialPageRoute<void>(
  builder: (_) => const ReviewInboxScreen(),
  fullscreenDialog: true,
);

class ReviewInboxScreen extends ConsumerWidget {
  const ReviewInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final proposals = ref.watch(pendingProposalsProvider);

    return Scaffold(
      backgroundColor: colors.appBackground,
      appBar: AppBar(
        backgroundColor: colors.appBackground,
        title: Text(
          'Differences',
          style: uiHeaderTextStyle(size: 18, color: colors.text),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(pendingProposalsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: proposals.isEmpty
          ? Center(
              child: Text(
                'No changes are waiting for review.',
                style: uiTextStyle(size: 13, color: colors.muted),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(DsSpace.pane),
              itemCount: proposals.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: DsSpace.islandGap),
              itemBuilder: (context, index) => _ProposalCard(
                proposal: proposals[index],
                onOpen: () =>
                    Navigator.of(context).push(diffRoute(proposals[index])),
              ),
            ),
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal, required this.onOpen});

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
    return DsIsland(
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.selection,
                  borderRadius: const BorderRadius.all(DsRadius.control),
                ),
                child: Icon(Icons.difference_outlined, color: colors.text),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proposal.content.title.isEmpty
                          ? proposal.proposedPath ?? 'Document change'
                          : proposal.content.title,
                      style: uiTextStyle(
                        size: 14,
                        weight: 600,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$operation · ${proposal.authorDisplayName} · '
                      '${proposal.updatedAt.toLocal()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: uiTextStyle(size: 11, color: colors.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
