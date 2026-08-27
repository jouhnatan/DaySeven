import 'package:dayseven/features/editing_toolbar/ui/controls/alignment_controls.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/bold_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/divider_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/heading_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/italic_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/strikethrough_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/underline_control.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: dsTheme(),
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('each modifier module owns its icon, label, and callback', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var pressed = '';
      await tester.pumpWidget(
        app(
          Row(
            children: [
              BoldControl(active: true, onPressed: () => pressed = 'bold'),
              ItalicControl(active: false, onPressed: () => pressed = 'italic'),
              StrikethroughControl(
                active: false,
                onPressed: () => pressed = 'strikethrough',
              ),
              UnderlineControl(
                active: false,
                onPressed: () => pressed = 'underline',
              ),
            ],
          ),
        ),
      );

      for (final (icon, tooltip) in const [
        (Icons.format_bold, 'Bold (CTRL+B)'),
        (Icons.format_italic, 'Italics (CTRL+I)'),
        (Icons.format_strikethrough, 'Strikethrough (CTRL+SHIFT+X)'),
        (Icons.format_underlined, 'Underline (CTRL+U)'),
      ]) {
        expect(find.byIcon(icon), findsOneWidget);
        expect(
          tester
              .widget<Tooltip>(
                find.ancestor(
                  of: find.byIcon(icon),
                  matching: find.byType(Tooltip),
                ),
              )
              .message,
          tooltip,
        );
      }

      final bold = tester.widget<DsButton>(
        find.ancestor(
          of: find.byIcon(Icons.format_bold),
          matching: find.byType(DsButton),
        ),
      );
      expect(bold.active, isTrue);

      await tester.tap(find.byIcon(Icons.format_strikethrough));
      expect(pressed, 'strikethrough');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('alignment module reports state and sends the chosen alignment', (
    tester,
  ) async {
    BlockAlign? picked;
    await tester.pumpWidget(
      app(
        AlignmentControls(
          align: BlockAlign.center,
          onPick: (value) => picked = value,
        ),
      ),
    );

    // Three exclusive options are one framed strip, so the chosen cell is
    // raised out of the frame in paper rather than filled with the accent.
    expect(find.byType(DsSegmented<BlockAlign>), findsOneWidget);

    final ds = DsColors.cream;
    Color cellFill(IconData icon) => (tester
                .widget<AnimatedContainer>(
                  find
                      .ancestor(
                        of: find.byIcon(icon),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration)
        .color!;

    expect(cellFill(Icons.format_align_center), ds.island);
    expect(cellFill(Icons.format_align_left), isNot(ds.island));
    expect(cellFill(Icons.format_align_right), isNot(ds.island));

    await tester.tap(find.byIcon(Icons.format_align_right));
    expect(picked, BlockAlign.right);
  });

  testWidgets('heading module distinguishes dismissal from body text', (
    tester,
  ) async {
    var sentinel = 99;
    await tester.pumpWidget(
      app(
        HeadingControl(level: null, onPick: (value) => sentinel = value ?? 0),
      ),
    );

    await tester.tap(find.byIcon(Icons.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 3'));
    await tester.pumpAndSettle();
    expect(sentinel, 3);

    await tester.tap(find.byIcon(Icons.title));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body text'));
    await tester.pumpAndSettle();
    expect(sentinel, 0);
  });

  testWidgets('divider module owns its icon, label, and callback', (
    tester,
  ) async {
    var pressed = false;
    await tester.pumpWidget(
      app(DividerControl(onPressed: () => pressed = true)),
    );

    expect(find.byIcon(Icons.horizontal_rule), findsOneWidget);
    expect(
      tester
          .widget<Tooltip>(
            find.ancestor(
              of: find.byIcon(Icons.horizontal_rule),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      'Insert divider',
    );
    await tester.tap(find.byIcon(Icons.horizontal_rule));
    expect(pressed, isTrue);
  });
}
