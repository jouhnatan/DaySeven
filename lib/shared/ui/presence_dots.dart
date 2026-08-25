/// The collaborator dots: a small stack of initials showing who is where.
///
/// Lives in shared/ui because the Knowledge Base tree, the editor and the
/// bottom bar all draw it, and no feature may import another.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/presence/peer_presence.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// The colour a person is drawn in, consistent on both machines.
Color presenceColorFor(String userId) =>
    DsPresence.palette[presenceColorIndex(userId, DsPresence.palette.length)];

/// A stack of up to [maxVisible] initials, with a `+N` cap beyond that.
///
/// Renders nothing at all when there is nobody, so callers can place it
/// unconditionally in a row without leaving a gap behind.
class PresenceDots extends StatelessWidget {
  const PresenceDots({
    super.key,
    required this.peers,
    this.size = DsPresence.dotSize,
    this.maxVisible = 3,
  });

  final List<PeerPresence> peers;
  final double size;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) return const SizedBox.shrink();

    final shown = peers.take(maxVisible).toList(growable: false);
    final overflow = peers.length - shown.length;
    final colors = context.ds;
    final overlap = size * (DsPresence.dotOverlap / DsPresence.dotSize);

    final dots = <Widget>[
      for (final peer in shown)
        _Dot(
          label: peer.initial,
          color: presenceColorFor(peer.userId),
          size: size,
          idle: peer.idle,
        ),
      if (overflow > 0)
        _Dot(
          label: '+$overflow',
          color: colors.muted,
          size: size,
          idle: false,
        ),
    ];

    return Tooltip(
      message: _describe(peers),
      child: Semantics(
        label: _describe(peers),
        child: SizedBox(
          height: size,
          width: size + (dots.length - 1) * (size - overlap),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < dots.length; i++)
                Positioned(left: i * (size - overlap), child: dots[i]),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Alice is here", "Alice and Bru are here", "Alice, Bru and 1 other".
/// Written out rather than listing bare names so the tooltip reads as a
/// sentence at any count.
String _describe(List<PeerPresence> peers) {
  final names = peers.map((peer) {
    final suffix = peer.idle ? ' (idle)' : '';
    return '${peer.label}$suffix';
  }).toList(growable: false);
  final joined = switch (names.length) {
    0 => '',
    1 => names.first,
    2 => '${names[0]} and ${names[1]}',
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
  return names.length == 1 ? '$joined is here' : '$joined are here';
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.label,
    required this.color,
    required this.size,
    required this.idle,
  });

  final String label;
  final Color color;
  final double size;

  /// An idle peer is drawn hollow — still present, but not to be waited on.
  final bool idle;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: idle ? colors.island : color,
        shape: BoxShape.circle,
        border: Border.all(color: idle ? color : colors.island, width: 1),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: uiTextStyle(
          size: size * (9 / DsPresence.dotSize),
          weight: 600,
          color: idle ? color : colors.island,
          height: 1,
        ),
      ),
    );
  }
}
