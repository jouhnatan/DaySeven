/// Reusable entry points for complete and document-contextual Differences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/ui/review_edits_screen.dart';

void openAllDifferences(WidgetRef ref) {
  ref.read(viewProvider.notifier).state = DsView.differences;
}

/// Opens only proposals for [documentId]. A single match opens directly; a
/// multi-author set opens the same review screen with previous/next navigation.
bool openDifferencesForDocument(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) {
  final proposals = ref
      .read(differencesStateProvider)
      .proposals
      .where((proposal) => proposal.targetDocumentId == documentId)
      .toList(growable: false);
  if (proposals.isEmpty) return false;
  Navigator.of(context).push(
    reviewEditsRoute(
      proposals: proposals,
      initialProposalId: proposals.first.id,
    ),
  );
  return true;
}
