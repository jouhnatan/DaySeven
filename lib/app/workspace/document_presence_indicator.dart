/// Who else is in the open document, shown beside the review-sync state.
///
/// This is the surface that survives the two copies having drifted apart. A
/// collaborator sitting on a block that only exists in their copy — because
/// their proposal has not been approved yet — cannot have a marker drawn
/// against any block here, but they are still in the document, and this says
/// so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/presence.dart';
import 'package:dayseven/shared/ui/presence_dots.dart';

class DocumentPresenceIndicator extends ConsumerWidget {
  const DocumentPresenceIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(peersInOpenDocumentProvider);
    if (peers.isEmpty) return const SizedBox.shrink();
    return Padding(
      key: const Key('document-presence'),
      padding: const EdgeInsets.only(right: 6),
      child: PresenceDots(peers: peers),
    );
  }
}
