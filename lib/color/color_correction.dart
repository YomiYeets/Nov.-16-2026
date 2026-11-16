// Correcting the photo's colors using the printed reference card.
//
// THE PROBLEM
// The color a camera records depends on more than the object: the light
// (sunlight, shade, overcast and indoor bulbs all differ), the exposure, the
// phone's automatic white balance, and its built-in "make it look nice" tone
// curve. The same strip photographed twice can come out with quite different
// RGB values.
//
// THE IDEA
// We put a card with patches of KNOWN color in the same photo, under the same
// light. Whatever the camera did to the patches, it also did to the pad. So we
// find the transformation that turns the measured patch colors back into
// their known values, and apply the same transformation to the pad.
//
// THE MODEL (two stages, both on linear RGB)
//
//   Stage 1, per-channel tone curves (from the GRAY patches).
//     For neutral grays, the true R, G and B are equal and known. Plotting
//     measured R against true R for the six grays shows how the camera's
//     red channel responds to light; the same goes for G and B. We join these
//     points with straight lines (a piecewise-linear curve) and use the curve
//     to undo the response. This one step fixes exposure, white balance
//     (each channel gets its own curve) and much of the phone's non-linear
//     tone mapping.
//
//   Stage 2, a 3x4 affine color matrix (from ALL patches).
//     After stage 1 the grays are right, but saturated colors can still be
//     off because the camera's red/green/blue sensitivities are not the same
//     as the sRGB primaries (channel "cross-talk"). We fit
//
//         [R']   [m00 m01 m02 m03] [R]
//         [G'] = [m10 m11 m12 m13] [G]
//         [B']   [m20 m21 m22 m23] [B]
//                                  [1]
//
//     by least squares over all 18 patches (54 equations, 12 unknowns). The
//     fourth column is an offset that absorbs flare (stray light that
//     lightens everything a little). The pink patches sit in the same region
//     of color space as the pad, so we give them extra weight: we care most
//     about being right where the pad colors are.
//
//     A small "ridge" penalty pulls the matrix towards the identity, so a
//     poor photo can't produce a wild matrix that fits the patches but
//     distorts everything else.
//
// QUALITY CHECK
// After fitting, we convert each corrected patch to Lab and compare it with
// its known Lab value. The RMS of those ΔE values is the "card fit error". If
// it is large, the photo is unreliable (glare on the card, mis-tapped
// corners, mixed lighting) and the app warns you.

import 'dart:math' as math;

import 'color_space.dart';
import 'linalg.dart';
import 'vec3.dart';

/// A monotonic piecewise-linear function y = f(x), extended by straight lines
/// beyond the first and last points.
class PiecewiseLinear {
  final List<double> xs, ys;
  PiecewiseLinear._(this.xs, this.ys);

  static PiecewiseLinear identity() => PiecewiseLinear._([0, 1], [0, 1]);

  /// Builds a curve from unordered (x, y) pairs. Points are sorted by x and y
  /// is forced to be non-decreasing: more light in must never mean less light
  /// out. Points closer than 1e-4 in x are merged.
  factory PiecewiseLinear.fit(List<double> x, List<double> y) {
    final idx = List<int>.generate(x.length, (i) => i)
      ..sort((a, b) => x[a].compareTo(x[b]));
    final xs = <double>[], ys = <double>[];
    for (final i in idx) {
      if (xs.isNotEmpty && (x[i] - xs.last).abs() < 1e-4) {
        ys[ys.length - 1] = (ys.last + y[i]) / 2;
        continue;
      }
      xs.add(x[i]);
      ys.add(y[i]);
    }
    for (var i = 1; i < ys.length; i++) {
      if (ys[i] < ys[i - 1]) ys[i] = ys[i - 1];
    }
    if (xs.length < 2) return identity();
    return PiecewiseLinear._(xs, ys);
  }

  double call(double v) {
    var i = 0;
    if (v <= xs.first) {
      i = 0;
    } else if (v >= xs.last) {
      i = xs.length - 2;
    } else {
      while (v > xs[i + 1]) {
        i++;
      }
    }
    final t = (v - xs[i]) / (xs[i + 1] - xs[i]);
    return ys[i] + t * (ys[i + 1] - ys[i]);
  }
}

/// One patch's input to the fit.
class PatchObservation {
  /// Measured color in the photo, linear RGB.
  final Vec3 measured;

  /// Known (reference) color, linear RGB.
  final Vec3 reference;

  /// True for the neutral gray ramp (used for the stage-1 tone curves).
  final bool isGray;

  /// Relative importance in the stage-2 matrix fit.
  final double weight;

  const PatchObservation(this.measured, this.reference,
      {this.isGray = false, this.weight = 1});
}

class ColorCorrection {
  final List<PiecewiseLinear> toneCurves; // R, G, B
  final List<List<double>> matrix; // 3 rows x 4 columns
  final List<double> patchDeltaE;
  final double rmsDeltaE;

  ColorCorrection._(this.toneCurves, this.matrix, this.patchDeltaE, this.rmsDeltaE);

  /// Identity correction (for tests and fallback).
  factory ColorCorrection.identity() => ColorCorrection._(
        List.generate(3, (_) => PiecewiseLinear.identity()),
        [
          [1, 0, 0, 0],
          [0, 1, 0, 0],
          [0, 0, 1, 0],
        ],
        const [],
        0,
      );

  static ColorCorrection fit(List<PatchObservation> patches, {double ridge = 1e-3}) {
    // ---- Stage 1: tone curves from the gray patches -----------------------
    final grays = patches.where((p) => p.isGray).toList();
    final curves = <PiecewiseLinear>[];
    for (var ch = 0; ch < 3; ch++) {
      if (grays.length >= 2) {
        // Anchor (0,0): with no light, the corrected value is zero too. This
        // keeps the curve sensible below the darkest patch.
        curves.add(PiecewiseLinear.fit(
          [0.0, ...grays.map((g) => g.measured[ch])],
          [0.0, ...grays.map((g) => g.reference[ch])],
        ));
      } else {
        curves.add(PiecewiseLinear.identity());
      }
    }
    Vec3 tone(Vec3 v) => Vec3(curves[0](v.x), curves[1](v.y), curves[2](v.z));

    // ---- Stage 2: affine matrix by weighted, ridge-regularized LSQ --------
    final rows = <List<double>>[];
    final weights = <double>[];
    final toned = patches.map((p) => tone(p.measured)).toList();
    for (var i = 0; i < patches.length; i++) {
      rows.add([toned[i].x, toned[i].y, toned[i].z, 1.0]);
      weights.add(patches[i].weight);
    }
    // Ridge: extra "pseudo-observations" that say "row ch of the matrix should
    // look like row ch of the identity". Their weight is tiny compared with
    // the real patches, so they only matter if the patches can't pin the
    // matrix down.
    final lambda = ridge * patches.length;
    final matrix = <List<double>>[];
    for (var ch = 0; ch < 3; ch++) {
      final r = [...rows];
      final w = [...weights];
      final y = [for (final p in patches) p.reference[ch]];
      for (var k = 0; k < 4; k++) {
        final e = List<double>.filled(4, 0)..[k] = 1;
        r.add(e);
        w.add(lambda);
        y.add(k == ch ? 1.0 : 0.0);
      }
      matrix.add(leastSquares(r, y, weights: w));
    }

    final partial = ColorCorrection._(curves, matrix, const [], 0);
    // ---- Quality: ΔE of each corrected patch vs its known value -----------
    final des = [
      for (final p in patches)
        deltaE76(linearRgbToLab(partial.apply(p.measured)), linearRgbToLab(p.reference))
    ];
    final rms = des.isEmpty
        ? 0.0
        : math.sqrt(des.map((d) => d * d).reduce((a, b) => a + b) / des.length);
    return ColorCorrection._(curves, matrix, des, rms);
  }

  /// Applies the correction to a measured linear RGB color.
  Vec3 apply(Vec3 measured) {
    final t = Vec3(toneCurves[0](measured.x), toneCurves[1](measured.y),
        toneCurves[2](measured.z));
    double row(int ch) {
      final m = matrix[ch];
      return m[0] * t.x + m[1] * t.y + m[2] * t.z + m[3];
    }

    return Vec3(row(0), row(1), row(2));
  }
}
