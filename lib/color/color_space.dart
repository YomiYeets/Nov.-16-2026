// Color-space conversions: sRGB  <->  linear RGB  <->  CIE XYZ  <->  CIELAB.
//
// WHY SO MANY SPACES?
//
// 1. A phone JPEG stores *encoded* sRGB values (0..255). The encoding is
//    deliberately non-linear (a "gamma" curve of roughly power 1/2.2) so that
//    8 bits are spent where human vision is most sensitive. A pixel value of
//    128 is NOT half the light of 255; it is about 22% of it.
//
// 2. Light adds up linearly. Averaging pixels, correcting white balance and
//    mixing colors are only physically meaningful on *linear* values, so we
//    undo the sRGB curve first ("linearize").
//
// 3. Linear RGB is still tied to particular red/green/blue primaries. Matrix
//    multiplication converts it to CIE XYZ, a device-independent description
//    of a color defined by the CIE in 1931 from human color-matching
//    experiments. Y is luminance.
//
// 4. XYZ is not perceptually uniform: equal numeric steps do not look like
//    equal color differences. CIELAB (1976) applies a cube-root compression
//    so that Euclidean distance roughly matches perceived difference:
//        L*  lightness, 0 (black) .. 100 (white)
//        a*  green (-) .. red/magenta (+)
//        b*  blue (-)  .. yellow (+)
//    The distance between two Lab colors is "Delta E" (ΔE*ab, CIE76).
//    ΔE ≈ 1 is about the smallest difference a trained eye can see side by
//    side; ΔE ≈ 2–3 is noticeable to most people.
//
//    Nitrate pads change from white to magenta, mostly a fall in L* and a
//    rise in a*, so CIELAB makes the "how far along the color scale is it?"
//    question a geometric one (see calibration_curve.dart).

import 'dart:math' as math;

import 'vec3.dart';

/// sRGB encoded value (0..1) -> linear light (0..1).
///
/// IEC 61966-2-1: a short linear segment near black, then a 2.4 power curve.
/// The overall shape is close to a 2.2 gamma.
double srgbToLinear(double c) {
  if (c <= 0.04045) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

/// Linear light (0..1) -> sRGB encoded value (0..1). Inverse of [srgbToLinear].
double linearToSrgb(double c) {
  if (c <= 0.0031308) return 12.92 * c;
  return 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
}

/// Lookup table: 8-bit sRGB code value -> linear light. 256 entries, so we
/// avoid calling pow() for every pixel of a 12-megapixel photo.
final List<double> srgb8ToLinearLut =
    List<double>.generate(256, (i) => srgbToLinear(i / 255.0), growable: false);

Vec3 srgb8ToLinear(int r, int g, int b) =>
    Vec3(srgb8ToLinearLut[r], srgb8ToLinearLut[g], srgb8ToLinearLut[b]);

Vec3 srgbVecToLinear(Vec3 s) =>
    Vec3(srgbToLinear(s.x), srgbToLinear(s.y), srgbToLinear(s.z));

Vec3 linearVecToSrgb(Vec3 l) =>
    Vec3(linearToSrgb(l.x), linearToSrgb(l.y), linearToSrgb(l.z));

// Linear sRGB -> XYZ matrix for the D65 white point (daylight, ~6500 K).
// Each column is the XYZ of one primary (red, green, blue) at full intensity.
// The middle row gives luminance:  Y = 0.2126 R + 0.7152 G + 0.0722 B.
// Green contributes most because our eyes are most sensitive to it.
const List<List<double>> _rgbToXyz = [
  [0.4124564, 0.3575761, 0.1804375],
  [0.2126729, 0.7151522, 0.0721750],
  [0.0193339, 0.1191920, 0.9503041],
];

const List<List<double>> _xyzToRgb = [
  [3.2404542, -1.5371385, -0.4985314],
  [-0.9692660, 1.8760108, 0.0415560],
  [0.0556434, -0.2040259, 1.0572252],
];

/// Reference white (D65) in XYZ, scaled so Y = 1.
const Vec3 d65White = Vec3(0.95047, 1.0, 1.08883);

Vec3 _mul(List<List<double>> m, Vec3 v) => Vec3(
      m[0][0] * v.x + m[0][1] * v.y + m[0][2] * v.z,
      m[1][0] * v.x + m[1][1] * v.y + m[1][2] * v.z,
      m[2][0] * v.x + m[2][1] * v.y + m[2][2] * v.z,
    );

Vec3 linearRgbToXyz(Vec3 rgb) => _mul(_rgbToXyz, rgb);
Vec3 xyzToLinearRgb(Vec3 xyz) => _mul(_xyzToRgb, xyz);

// CIELAB constants. Below a small threshold the cube root is replaced by a
// straight line so the function stays well behaved near black.
const double _eps = 216 / 24389; // (6/29)^3
const double _kappa = 24389 / 27; // (29/3)^3

double _f(double t) => t > _eps ? math.pow(t, 1 / 3).toDouble() : (_kappa * t + 16) / 116;

double _fInv(double f) {
  final f3 = f * f * f;
  return f3 > _eps ? f3 : (116 * f - 16) / _kappa;
}

/// XYZ -> CIELAB relative to [white].
///
///   L* = 116 f(Y/Yn) - 16
///   a* = 500 [ f(X/Xn) - f(Y/Yn) ]
///   b* = 200 [ f(Y/Yn) - f(Z/Zn) ]
///
/// Dividing by the white point makes Lab describe color relative to "paper
/// white", which is why correcting the photo to the reference card first
/// matters so much.
Vec3 xyzToLab(Vec3 xyz, {Vec3 white = d65White}) {
  final fx = _f(xyz.x / white.x);
  final fy = _f(xyz.y / white.y);
  final fz = _f(xyz.z / white.z);
  return Vec3(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
}

Vec3 labToXyz(Vec3 lab, {Vec3 white = d65White}) {
  final fy = (lab.x + 16) / 116;
  final fx = fy + lab.y / 500;
  final fz = fy - lab.z / 200;
  return Vec3(_fInv(fx) * white.x, _fInv(fy) * white.y, _fInv(fz) * white.z);
}

Vec3 linearRgbToLab(Vec3 rgb) => xyzToLab(linearRgbToXyz(rgb));
Vec3 labToLinearRgb(Vec3 lab) => xyzToLinearRgb(labToXyz(lab));

/// Lab -> 8-bit sRGB for drawing swatches on screen (clamped to 0..255).
List<int> labToSrgb8(Vec3 lab) {
  final s = linearVecToSrgb(labToLinearRgb(lab));
  int c(double v) => (v.clamp(0.0, 1.0) * 255).round();
  return [c(s.x), c(s.y), c(s.z)];
}

/// CIE76 color difference: plain Euclidean distance in Lab.
///
/// Newer formulas (CIEDE2000) match perception a little better, but they are
/// not Euclidean. The calibration curve does geometry (projecting a point onto
/// a line), which needs a true distance, so we use ΔE76 throughout.
double deltaE76(Vec3 lab1, Vec3 lab2) => lab1.distanceTo(lab2);

/// Relative luminance (Y) of a linear RGB color.
double luminance(Vec3 rgb) => 0.2126729 * rgb.x + 0.7151522 * rgb.y + 0.0721750 * rgb.z;
