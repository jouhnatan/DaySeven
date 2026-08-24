/// The Notifications island: the latest five events, newest at the top.
///
/// A new notification fades in while the rows beneath it slide down one
/// notch; the row that falls past five slides out.
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
          (context, animation) => _row(removed, animation),
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
        padding: const EdgeInsets.all(6),
        child:
            _items.isEmpty ? const _EmptyNotifications() : _buildAnimatedList(),
      ),
    );
  }

  Widget _buildAnimatedList() {
    return AnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        if (index >= _items.length) return const SizedBox.shrink();
        return _row(_items[index], animation);
      },
    );
  }

  Widget _row(DsNotification notification, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: animation,
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: _NotificationRow(notification: notification),
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

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification});

  final DsNotification notification;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Row(
      children: [
        Icon(_kindIcon(notification.kind), size: 13, color: colors.muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            notification.message,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: uiTextStyle(size: 11, color: colors.text),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          formatNotificationAge(notification.createdAt),
          style: uiTextStyle(size: 10, color: colors.muted),
        ),
      ],
    );
  }
}
