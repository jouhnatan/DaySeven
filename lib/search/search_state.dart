/// What the search bar is asking, and what the index answers.
///
/// The query is held here rather than in the field so that anything else can
/// read what is being searched for, and so results survive the bar losing focus.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/blocks/search_index.dart';

/// The live query behind the top search bar.
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Results recomputed on every query change, straight from the local index.
final searchResultsProvider = Provider<List<SearchHit>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final session = ref.watch(kbSessionProvider);
  if (session == null || query.trim().isEmpty) return const [];
  return session.index.search(query);
});
