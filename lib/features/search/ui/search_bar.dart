/// The Search field injected into the Editor's fixed overlay shelf.
///
/// Shaped after Spotlight: a single rounded field, wider than it is tall, set
/// on its own rather than stretched across the window. Results come from the
/// Knowledge Base's local FTS index and update on every keystroke, so matching
/// files appear while the user is still typing a word.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:dayseven/features/search/state/search_state.dart';

/// A little narrower and shorter than macOS Spotlight, which is roughly
/// 680 x 60.
const double kSearchWidth = 560;
const double kSearchHeight = 40;

class DsSearchBar extends ConsumerStatefulWidget {
  const DsSearchBar({super.key, this.resultsAbove = false});

  /// Opens results above the field when Search is anchored to the bottom edge.
  final bool resultsAbove;

  @override
  ConsumerState<DsSearchBar> createState() => _DsSearchBarState();
}

class _DsSearchBarState extends ConsumerState<DsSearchBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _hideResults();
    });
  }

  @override
  void dispose() {
    _hideResults();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _showResults() {
    if (_overlay != null) return;
    // The panel hangs directly under the field, matching its width.
    final width =
        (context.findRenderObject() as RenderBox?)?.size.width ?? kSearchWidth;
    _overlay = OverlayEntry(
      builder: (context) => Positioned(
        width: width,
        child: CompositedTransformFollower(
          link: _layerLink,
          targetAnchor: widget.resultsAbove
              ? Alignment.topLeft
              : Alignment.bottomLeft,
          followerAnchor: widget.resultsAbove
              ? Alignment.bottomLeft
              : Alignment.topLeft,
          offset: Offset(0, widget.resultsAbove ? -4 : 4),
          // Keep result clicks in the field's tap region. Otherwise TextField
          // unfocuses on mouse-down and removes this overlay before the row's
          // onTap can run on mouse-up.
          child: TextFieldTapRegion(
            child: _ResultsPanel(
              onOpen: (hit) {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).state = '';
                _hideResults();
                _focus.unfocus();
                _open(hit);
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _hideResults() {
    _overlay?.remove();
    _overlay = null;
  }

  Future<void> _open(SearchHit hit) async {
    await ref.read(documentControllerProvider.notifier).open(hit.relativePath);
    ref.read(viewProvider.notifier).state = DsView.editor;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kSearchWidth),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Container(
          height: kSearchHeight,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.island,
            borderRadius: const BorderRadius.all(DsRadius.control),
            border: Border.all(color: colors.border, width: 1),
          ),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            style: uiTextStyle(size: 15, color: colors.text),
            cursorColor: colors.text,
            cursorWidth: 1.5,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search',
              hintStyle: uiTextStyle(size: 15, color: colors.muted),
            ),
            onChanged: (value) {
              ref.read(searchQueryProvider.notifier).state = value;
              if (value.trim().isEmpty) {
                _hideResults();
              } else {
                _showResults();
              }
            },
          ),
        ),
      ),
    );
  }
}

class _ResultsPanel extends ConsumerWidget {
  const _ResultsPanel({required this.onOpen});

  final void Function(SearchHit hit) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final results = ref.watch(searchResultsProvider);
    if (results.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 340),
        decoration: BoxDecoration(
          color: colors.island,
          borderRadius: const BorderRadius.all(DsRadius.island),
          border: Border.all(color: colors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView.builder(
          padding: const EdgeInsets.all(4),
          shrinkWrap: true,
          itemCount: results.length,
          itemBuilder: (context, i) =>
              _ResultRow(hit: results[i], onTap: () => onOpen(results[i])),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsHoverRow(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hit.title.isEmpty ? hit.relativePath : hit.title,
            style: uiTextStyle(size: 13, weight: 500, color: colors.text),
          ),
          if (hit.snippet.isNotEmpty) ...[
            const SizedBox(height: 2),
            _Snippet(hit.snippet),
          ],
        ],
      ),
    );
  }
}

/// Renders the FTS snippet, emphasising the matched terms the index marked.
class _Snippet extends StatelessWidget {
  const _Snippet(this.snippet);

  final String snippet;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final base = uiTextStyle(size: 12, color: colors.muted);
    final spans = <TextSpan>[];
    var rest = snippet;

    while (true) {
      final start = rest.indexOf(SearchHit.matchOpen);
      if (start < 0) break;
      final end = rest.indexOf(SearchHit.matchClose, start);
      if (end < 0) break;

      if (start > 0) spans.add(TextSpan(text: rest.substring(0, start)));
      spans.add(
        TextSpan(
          text: rest.substring(start + 1, end),
          style: uiTextStyle(size: 12, weight: 600, color: colors.text),
        ),
      );
      rest = rest.substring(end + 1);
    }
    if (rest.isNotEmpty) spans.add(TextSpan(text: rest));

    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
