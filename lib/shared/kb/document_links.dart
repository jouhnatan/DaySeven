/// Portable links between Markdown documents in one Knowledge Base.
library;

import 'package:path/path.dart' as p;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/kb/paths.dart';

/// A local Markdown target resolved relative to the document containing it.
class DocumentLinkTarget {
  const DocumentLinkTarget({required this.path, required this.fragment});

  final String path;
  final String fragment;
}

bool isDocumentLinkHref(String? href) {
  if (href == null || href.isEmpty) return false;
  final hash = href.indexOf('#');
  final path = (hash < 0 ? href : href.substring(0, hash)).toLowerCase();
  return path.endsWith(kDocumentExtension) ||
      path.endsWith(kLegacyDocumentExtension);
}

DocumentLinkTarget? resolveDocumentLink(
  String sourcePath,
  String? href, {
  Set<String>? documentPaths,
}) {
  if (href == null || href.isEmpty) return null;
  final uri = Uri.tryParse(href);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      href.startsWith('/')) {
    return null;
  }

  final hash = href.indexOf('#');
  final rawPath = hash < 0 ? href : href.substring(0, hash);
  final fragment = hash < 0 ? '' : href.substring(hash);
  if (rawPath.isEmpty) return null;

  if (!isDocumentLinkHref(href)) return null;

  final sourceFolder = p.posix.dirname(sourcePath);
  final resolved = p.posix.normalize(
    p.posix.join(sourceFolder == '.' ? '' : sourceFolder, rawPath),
  );
  if (resolved == '..' || resolved.startsWith('../')) return null;
  if (documentPaths != null && !documentPaths.contains(resolved)) return null;
  return DocumentLinkTarget(path: resolved, fragment: fragment);
}

String documentLinkHref(
  String sourcePath,
  String targetPath, {
  String fragment = '',
}) {
  final sourceFolder = p.posix.dirname(sourcePath);
  final relative = p.posix.relative(
    targetPath,
    from: sourceFolder == '.' ? '' : sourceFolder,
  );
  return '$relative$fragment';
}

String documentLinkLabel(String targetPath) =>
    documentTitleFromPath(targetPath);

/// Rewrites links after a file or folder moves from [fromPath] to [toPath].
///
/// [documents] is keyed by the paths that existed before the move. The result
/// is keyed by the paths at which the rewritten documents must be saved.
Map<String, BlockDocument> rewriteDocumentLinksForMove({
  required Map<String, BlockDocument> documents,
  required String fromPath,
  required String toPath,
  bool renameMovedDocumentTitle = false,
}) {
  final oldPaths = documents.keys.toSet();
  final rewritten = <String, BlockDocument>{};

  for (final entry in documents.entries) {
    final oldSource = entry.key;
    final newSource = relocatePath(oldSource, from: fromPath, to: toPath);
    var changed = false;

    List<TextSpanNode> rewriteSpans(List<TextSpanNode> spans) => [
      for (final span in spans)
        if (resolveDocumentLink(oldSource, span.href, documentPaths: oldPaths)
            case final target?)
          (() {
            final newTarget = relocatePath(
              target.path,
              from: fromPath,
              to: toPath,
            );
            final href = documentLinkHref(
              newSource,
              newTarget,
              fragment: target.fragment,
            );
            final label = documentLinkLabel(newTarget);
            if (href != span.href || label != span.text) changed = true;
            return span.copyWith(text: label, href: (_) => href);
          })()
        else
          span,
    ];

    final blocks = [
      for (final block in entry.value.blocks)
        switch (block) {
          final TextBlock text => text.withSpans(rewriteSpans(text.spans)),
          final TableBlock table => table.copyWith(
            rows: [
              for (final row in table.rows)
                [for (final cell in row) rewriteSpans(cell)],
            ],
          ),
          _ => block,
        },
    ];

    var document = entry.value.copyWith(blocks: blocks);
    if (renameMovedDocumentTitle && oldSource == fromPath) {
      final title = documentTitleFromPath(toPath);
      if (document.title != title) {
        changed = true;
        document = document.copyWith(title: title);
      }
    }
    if (changed) rewritten[newSource] = document.normalized();
  }

  return rewritten;
}
