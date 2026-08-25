/// The Notifications island: the latest five events, newest at the top.
///
/// A new notification fades in while the rows beneath it slide down one
/// notch; the row that falls past five slides out. Each row names the
/// generic action in its header; tapping it lerps the more specific subtext
/// open beneath.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/notifications/domain/format_notification_age.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class NotificationsPanel extends ConsumerStatefulWidget {
  const NotificationsPanel({super.key});

  @override
  ConsumerState<NotificationsPanel> createState() => _NotificationsPanelState();
}

class _NotificationsPanelState extends ConsumerState<NotificationsPanel> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<DsNotification> _items;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _items = List.unmodifiable(ref.read(notificationStoreProvider));
    ref.listenManual(notificationStoreProvider, (_, next) => _sync(next));
    if (_items.isNotEmpty) _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    if (_ticker != null || _items.isEmpty) return;
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _sync(List<DsNotification> next) {
    final old = _items;
    _items = List.unmodifiable(next);
    _startTicker();
    if (mounted) setState(() {});
    final list = _listKey.currentState;
    if (list == null) return;

    final nextIds = {for (final notification in next) notification.id};
    for (var i = old.length - 1; i >= 0; i--) {
      if (!nextIds.contains(old[i].id)) {
        final removed = old[i];
        list.removeItem(
          i,
          (context, animation) => _row(removed, animation, divider: false),
          duration: DsMotion.pane,
        );
      }
    }

    final oldIds = {for (final notification in old) notification.id};
    for (var i = 0; i < next.length; i++) {
      if (!oldIds.contains(next[i].id)) {
        list.insertItem(i, duration: DsMotion.pane);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DsIsland(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.pane),
        child: _items.isEmpty
            ? const _EmptyNotifications()
            : _buildAnimatedList(),
      ),
    );
  }

  Widget _buildAnimatedList() {
    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        if (index >= _items.length) return const SizedBox.shrink();
        return _row(
          _items[index],
          animation,
          divider: index < _items.length - 1,
        );
      },
    );
  }

  Widget _row(
    DsNotification notification,
    Animation<double> animation, {
    required bool divider,
  }) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _NotificationRow(notification: notification),
            ),
            if (divider)
              Container(
                key: const Key('notification-divider'),
                height: 1,
                color: context.ds.border,
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Center(
      widthFactor: 1,
      child: Text(
        'Nothing yet.',
        style: uiTextStyle(size: 11, color: context.ds.muted),
      ),
    );
  }
}

IconData _kindIcon(DsNotificationKind kind) => switch (kind) {
  DsNotificationKind.publish => Icons.cloud_upload_outlined,
  DsNotificationKind.sync => Icons.sync,
  DsNotificationKind.share => Icons.group_outlined,
  DsNotificationKind.error => Icons.error_outline,
};

class _NotificationRow extends StatefulWidget {
  const _NotificationRow({required this.notification});

  final DsNotification notification;

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final notification = widget.notification;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _kindIcon(notification.kind),
                  size: 13,
                  color: colors.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    notification.heading ?? _kindHeading(notification.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: uiTextStyle(
                      size: 11,
                      weight: 600,
                      color: colors.text,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  formatNotificationAge(notification.createdAt),
                  style: uiTextStyle(size: 10, color: colors.muted),
                ),
              ],
            ),
            AnimatedSize(
              duration: DsMotion.pane,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Text(
                  notification.detail ?? notification.message,
                  maxLines: _expanded ? null : 1,
                  overflow: _expanded
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
                  style: uiTextStyle(size: 10, color: colors.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _kindHeading(DsNotificationKind kind) => switch (kind) {
  DsNotificationKind.publish => 'Document Published',
  DsNotificationKind.sync => 'Sync Complete',
  DsNotificationKind.share => 'Knowledge Base Shared',
  DsNotificationKind.error => 'Something Went Wrong',
};
