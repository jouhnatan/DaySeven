/// The dimensions a World can use.
library;

/// Whether the world renderer presents a flat map or a globe.
enum WorldDimension {
  twoD('2d', '2D'),
  threeD('3d', '3D');

  const WorldDimension(this.id, this.label);

  /// The stable id written to a `.unearth` file.
  final String id;

  /// The label shown in controls.
  final String label;

  /// Reads a stored id, returning null when it is not one this build knows.
  static WorldDimension? parse(Object? value) {
    if (value is! String) return null;
    final id = value.trim().toLowerCase();
    for (final dimension in values) {
      if (dimension.id == id) return dimension;
    }
    return null;
  }
}
