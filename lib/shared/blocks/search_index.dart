/// Full-text search over a Knowledge Base.
///
/// Search is a feature of its own: the index here, the query and results in
/// `search_state.dart`, and the field in `search_bar.dart`. The rest of the app
/// touches it in two places only — the shell shows the bar, and the open
/// Knowledge Base owns the index's lifetime, since it opens and closes with the
/// bundle.
///
/// The index lives inside the bundle at `.settings/.index/search.sqlite` and is
/// entirely derived: delete it and it rebuilds from the folder on the next open.
/// Search is local, so results appear as the user types with no network
/// round-trip.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class SearchHit {
  const SearchHit({
    required this.relativePath,
    required this.title,
    required this.snippet,
  });

  final String relativePath;
  final String title;

  /// A short excerpt around the match, with the matched terms wrapped in
  /// [matchOpen]/[matchClose] so the UI can emphasise them. Private-use code
  /// points, so nothing a user could type collides with the markers.
  final String snippet;

  static const matchOpen = '\u{E000}';
  static const matchClose = '\u{E001}';
}

class SearchIndex {
  SearchIndex._(this._db, this._kb);

  final Database _db;
  final KnowledgeBase _kb;

  static Future<SearchIndex> openFor(KnowledgeBase kb) async {
    await Directory(kb.indexPath).create(recursive: true);
    final db = sqlite3.open(p.join(kb.indexPath, 'search.sqlite'));
    db.execute('''
      create virtual table if not exists documents using fts5(
        relative_path unindexed,
        title,
        body,
        tokenize = 'unicode61 remove_diacritics 2'
      );
    ''');
    return SearchIndex._(db, kb);
  }

  void close() => _db.close();

  /// Rebuilds the whole index from the files on disk. Called when a Knowledge
  /// Base is opened, which also repairs an index left stale by edits made to
  /// the folder while the app was closed.
  Future<void> rebuild() async {
    _db.execute('delete from documents;');
    final stmt = _db.prepare(
      'insert into documents (relative_path, title, body) values (?, ?, ?)',
    );
    try {
      await for (final file in _documentFiles()) {
        final relative = _kb.relativePathFor(file.path);
        try {
          // Through the Knowledge Base, so which format a document is in is
          // decided in exactly one place.
          final doc = await _kb.readDocument(relative);
          stmt.execute([
            relative,
            documentTitleFromPath(relative),
            doc.plainText,
          ]);
        } on FormatException {
          // A file that is not a valid document simply is not searchable.
          continue;
        }
      }
    } finally {
      stmt.close();
    }
  }

  Stream<File> _documentFiles() async* {
    final dir = Directory(_kb.documentsPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File || !isDocumentPath(entity.path)) continue;
      final relative = _kb.relativePathFor(entity.path);
      final segments = p.posix.split(relative);
      if (segments.any((part) => part.startsWith('.')) ||
          (segments.isNotEmpty && segments.first == kMetadataDirName)) {
        continue;
      }
      yield entity;
    }
  }

  /// Re-indexes one document. Called on every save.
  void upsert(String relativePath, BlockDocument document) {
    _db.execute('delete from documents where relative_path = ?', [
      relativePath,
    ]);
    _db.execute(
      'insert into documents (relative_path, title, body) values (?, ?, ?)',
      [relativePath, documentTitleFromPath(relativePath), document.plainText],
    );
  }

  void remove(String relativePath) => _db.execute(
    'delete from documents where relative_path = ?',
    [relativePath],
  );

  void rename(String fromPath, String toPath) => _db.execute(
    'update documents set relative_path = ?, title = ? '
    'where relative_path = ?',
    [toPath, documentTitleFromPath(toPath), fromPath],
  );

  /// Searches Markdown file names and body text. Matches on a prefix of the
  /// last word, so results narrow while the user is still typing it.
  List<SearchHit> search(String query, {int limit = 30}) {
    final match = _toMatchQuery(query);
    if (match == null) return const [];

    // Keep this as an SQL literal rather than a bound integer. In macOS AOT
    // builds, sqlite3 3.5.1 can segfault in sqlite3_bind_int64 while binding the
    // LIMIT after the three text values below. The value is internal (never user
    // input) and bounded here, so interpolating it does not weaken the query.
    final safeLimit = limit < 1 ? 1 : (limit > 100 ? 100 : limit);

    try {
      final rows = _db.select(
        '''
        select relative_path, title,
               snippet(documents, 2, ?, ?, '...', 12) as snip
        from documents
        where documents match ?
        order by bm25(documents, 4.0, 1.0)
        limit $safeLimit;
        ''',
        [SearchHit.matchOpen, SearchHit.matchClose, match],
      );

      return [
        for (final row in rows)
          SearchHit(
            relativePath: row['relative_path'] as String,
            title: row['title'] as String,
            snippet: (row['snip'] as String?) ?? '',
          ),
      ];
    } on SqliteException {
      // A half-typed query can still be syntactically invalid FTS; showing no
      // results is better than interrupting the user's typing with an error.
      return const [];
    }
  }

  /// Builds an FTS5 query. Every term is quoted so that punctuation the user
  /// types cannot be read as an FTS operator, and the final term gets a `*` so
  /// matching is live rather than only on completed words.
  static String? _toMatchQuery(String raw) {
    final terms = raw
        .split(RegExp(r'\s+'))
        .map((t) => t.replaceAll(RegExp(r'["*^:()-]'), '').trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (terms.isEmpty) return null;

    final parts = <String>[];
    for (var i = 0; i < terms.length; i++) {
      final quoted = '"${terms[i]}"';
      parts.add(i == terms.length - 1 ? '$quoted*' : quoted);
    }
    return parts.join(' AND ');
  }
}
