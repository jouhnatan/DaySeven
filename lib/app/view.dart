/// Which workspace view is selected from the Views menu.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DsView { home, editor, differences }

/// Cross-feature navigation belongs to the composition root: several features
/// can open the editor without depending directly on the Views feature.
final viewProvider = StateProvider<DsView>((ref) => DsView.home);
