/// The Notifications bell in the shell's top bar, and the panel it opens.
///
/// The panel is an anchored overlay rather than a popup menu: menu items
/// swallow the taps a notification row needs to expand its detail. It hangs
/// from an [OverlayPortal] rather than an [OverlayEntry] of its own, so the
/// panel — and the minute ticker inside it — is disposed with the button that
/// owns it rather than outliving it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/notifications/ui/notifications_panel.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// Wide enough for a heading and its timestamp on one line, which the rail
/// this replaced never was.
const double kNotificationsPanelWidth = 320;
const double kNotificationsPanelHeight = 360;

class NotificationsBellButton extends ConsumerStatefulWidget {
  const NotificationsBellButton({super.key});

  @override
  ConsumerState<NotificationsBellButton> createState() =>
      _NotificationsBellButtonState();
}

class _NotificationsBellButtonState
    extends ConsumerState<NotificationsBellButton> {
  final _layerLink = LayerLink();
  final _portal = OverlayPortalController();

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    // The store is capped at five and starts empty every launch, so there is
    // no read state to track: having anything at all is the whole signal.
    final hasNotifications = ref.watch(notificationStoreProvider).isNotEmpty;
    final open = _portal.isShowing;

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) => Stack(
          children: [
            // Anywhere outside the panel dismisses it.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(_portal.hide),
              ),
            ),
            Positioned(
              width: kNotificationsPanelWidth,
              child: CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                // The panel hangs from the bottom of the top bar rather than
                // from the bell, which is inset within it.
                offset: Offset(0, dsMenuAnchorDrop(context)),
                child: const _NotificationsPopover(),
              ),
            ),
          ],
        ),
        child: Tooltip(
          message: 'Notifications',
          child: SizedBox.square(
            key: const Key('notifications-bell-button'),
            dimension: 34,
            child: DsButton(
              height: 34,
              padding: EdgeInsets.zero,
              highlight: colors.selection,
              active: open,
              semanticLabel: 'Notifications',
              onPressed: () => setState(_portal.toggle),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 18,
                    color: open ? colors.onFern : colors.text,
                  ),
                  if (hasNotifications)
                    Positioned(
                      top: 5,
                      right: 6,
                      child: Container(
                        key: const Key('notifications-bell-dot'),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: colors.pending,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The floating panel. A menu is above the page rather than on it, held apart
/// by its outline alone.
class _NotificationsPopover extends StatelessWidget {
  const _NotificationsPopover();

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const Key('notifications-popover'),
        height: kNotificationsPanelHeight,
        decoration: BoxDecoration(
          color: colors.bar,
          borderRadius: const BorderRadius.all(DsRadius.island),
          border: Border.all(color: colors.surfaceOutline, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsMenuHeader('Notifications'),
            Expanded(child: NotificationsPanel()),
          ],
        ),
      ),
    );
  }
}
