/// Represents the pixel offset for macOS window traffic lights.
class TrafficLightsOffset {
  const TrafficLightsOffset({
    this.x = defaultX,
    this.y = defaultY,
  });

  /// Default horizontal offset from the left edge of the window in logical pixels.
  /// Standard macOS position is ~8.0; 20.0 brings the buttons slightly to the right.
  static const double defaultX = 20.0;

  /// Default vertical offset from the top edge of the window in logical pixels.
  /// The shell's top bar is 48pt tall and the buttons are 14pt, so this
  /// centres them in the bar the rest of the chrome sits in.
  static const double defaultY = 17.0;

  /// Standard default offset that seats the traffic lights in the shell's top bar.
  static const TrafficLightsOffset standard = TrafficLightsOffset();

  /// Horizontal offset from the window left edge.
  final double x;

  /// Vertical offset from the window top edge.
  final double y;

  Map<String, dynamic> toMap() => {
    'x': x,
    'y': y,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrafficLightsOffset &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'TrafficLightsOffset(x: $x, y: $y)';
}
