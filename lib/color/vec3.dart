import 'dart:math' as math;

/// A tiny immutable 3-component vector.
///
/// We use it for every kind of 3-channel color in this app:
///   * encoded sRGB (r, g, b) in 0..1 — what a JPEG stores,
///   * linear RGB (r, g, b) in 0..1   — proportional to light intensity,
///   * CIE XYZ                         — device-independent tristimulus values,
///   * CIELAB (L*, a*, b*)             — a perceptual color space.
///
/// Which one a given Vec3 holds is documented at each use site.
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);

  static const zero = Vec3(0, 0, 0);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);
  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);
  Vec3 operator *(double s) => Vec3(x * s, y * s, z * s);
  Vec3 operator /(double s) => Vec3(x / s, y / s, z / s);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;
  double get length => math.sqrt(dot(this));
  double distanceTo(Vec3 o) => (this - o).length;

  double operator [](int i) => i == 0 ? x : (i == 1 ? y : z);
  List<double> toList() => [x, y, z];
  static Vec3 fromList(List<num> v) =>
      Vec3(v[0].toDouble(), v[1].toDouble(), v[2].toDouble());

  @override
  String toString() =>
      '(${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}, ${z.toStringAsFixed(3)})';
}
