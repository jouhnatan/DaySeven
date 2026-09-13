/// A slider for one bounded numeric value, drawn from the palette.
///
/// Sliders are not a separate visual idiom: this is the same track, thumb and
/// fern fill the World settings pane used before there was a second consumer.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/theme.dart';

class DsSlider extends StatelessWidget {
  const DsSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.width = 118,
    this.semanticFormatter,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  /// Non-null snaps the value to that many equal steps.
  final int? divisions;
  final double width;

  /// Speaks the value a screen reader cannot see. The visual read-out beside
  /// the slider is the caller's, so this is the caller's too.
  final String Function(double value)? semanticFormatter;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return SizedBox(
      width: width,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: colors.fern,
          inactiveTrackColor: colors.border,
          thumbColor: colors.fern,
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        ),
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          semanticFormatterCallback: semanticFormatter,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
