/// Path transformations shared by workspace state and persisted recents.
library;

import 'package:path/path.dart' as p;

/// Whether [path] is [ancestor] itself or a descendant of it.
bool isPathAtOrBelow(String path, String ancestor) =>
    path == ancestor || p.posix.isWithin(ancestor, path);

/// Repoints [path] when [from] or one of its containing folders moves to [to].
String relocatePath(String path, {required String from, required String to}) {
  if (!isPathAtOrBelow(path, from)) return path;
  if (path == from) return to;
  return p.posix.join(to, p.posix.relative(path, from: from));
}
