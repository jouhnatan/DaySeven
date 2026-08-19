/// Which service the left-hand rail is showing.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The left-hand rail lists services, not tools.
enum DsService { home, editor }

final serviceProvider = StateProvider<DsService>((ref) => DsService.home);
