/// Which workspace is placed in the shell's centre slot.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The two workspaces that can occupy the centre. They share one slot, so
/// placing one displaces the other; the Knowledge Base beside them is a pane
/// of its own and toggles independently.
enum DsView { editor, differences }

/// Cross-feature navigation belongs to the composition root: several features
/// can open the editor without depending directly on the Views feature.
final viewProvider = StateProvider<DsView>((ref) => DsView.editor);
