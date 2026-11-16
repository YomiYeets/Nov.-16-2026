// Turning a pad color (CIELAB) into a nitrate concentration.
//
// THE CALIBRATION PATH
// Photograph strips dipped in standards of known concentration (for example
// 0, 5, 10, 20 and 50 mg/L NO3-N). After color correction each standard gives
// a point in Lab space. Joining the averaged points in order of concentration
// gives a polyline, the "calibration path", that traces how the pad color
// moves through color space as nitrate rises (from near-white towards
// magenta: L* falls, a* rises).
//
//      L*
//       |  0 •
//       |      \
//       |       • 5
//       |        \
//       |         • 10
//       |           \__
//       |              • 20 ___
//       |                      • 50
//       +------------------------------ a*
//
// READING AN UNKNOWN
// 1. Project the unknown's Lab point onto the nearest segment of the path
//    (the closest point on the polyline).
// 2. Its fractional position t along that segment interpolates the
//    concentration linearly between the two standards:
//         C = C_i + t (C_{i+1} - C_i).
// 3. The perpendicular distance from the path is the "off-curve ΔE". A small
//    value means the color is consistent with the calibration. A large value
//    means it isn't: wrong timing, a different strip lot, interfering
//    substances, or a bad photo.
//
// This uses all three Lab coordinates at once, rather than (say) only a*,
// so it still works if the color moves in a curved path, and it averages
// noise across channels.
//
// WHY THIS CAN BEAT THE EYE
// The printed chart on a bottle offers only a few discrete blocks, and the
// eye can only bin a color into "between 10 and 20". The camera measures a
// continuous position between standards, averaged over thousands of pixels,
// and corrected for lighting. Real precision is still limited by the strip
// chemistry, so it has to be measured (see the uncertainty section below).
//
// UNCERTAINTY ("CONFIDENCE RANGE")
// We estimate how much the color of a strip scatters *along the path* when
// the concentration is the same:
//   * For every calibration standard measured more than once, take each
//     replicate's deviation from that standard's mean and project it onto
//     the local path direction. Pool these across all standards:
//         σ_along² = Σ (dev · tangent)² / Σ (n_level − 1)
//     Replicates should be separate strips and separate photos, so σ
//     includes everything that varies in practice: strip-to-strip chemistry,
//     timing, lighting and the color correction.
//   * If there are no replicates yet, we fall back on a default of 2 ΔE and
//     flag the range as provisional.
//   * Add the (tiny) pixel-averaging noise of this particular pad, and the
//     uncertainty of the calibration means themselves (σ/√n).
// We then step ±1.96σ along the path (an approximately 95% interval for a
// normally distributed error) and convert both ends to concentrations. Where
// the path is steep (the color changes a lot per mg/L) the range is narrow;
// where it is flat (typically at high concentrations, where the pad
// saturates) the same color noise turns into a wide concentration range.

import 'dart:math' as math;

import 'vec3.dart';

/// One calibration photo: a strip dipped in a standard of known
/// concentration, after color correction.
class CalibrationSample {
  final double concentration; // mg/L
  final Vec3 lab;
  const CalibrationSample(this.concentration, this.lab);
}

/// Averaged information for one concentration level.
class CalibrationLevel {
  final double concentration;
  final Vec3 meanLab;
  final int n;
  const CalibrationLevel(this.concentration, this.meanLab, this.n);
}

class ConcentrationEstimate {
  /// Best estimate, mg/L.
  final double value;

  /// Approximately 95% range, mg/L.
  final double low, high;

  /// The color is lighter than the lowest standard / darker than the highest.
  final bool belowRange, aboveRange;

  /// Perpendicular distance between the measured color and the path (ΔE).
  final double offCurveDeltaE;

  /// The σ (ΔE along the path) used for the range.
  final double sigmaDeltaE;

  /// Slope of the path where the reading landed: ΔE per mg/L.
  final double sensitivity;

  /// True if σ came from the default value (no replicates yet).
  final bool provisional;

  const ConcentrationEstimate({
    required this.value,
    required this.low,
    required this.high,
    required this.belowRange,
    required this.aboveRange,
    required this.offCurveDeltaE,
    required this.sigmaDeltaE,
    required this.sensitivity,
    required this.provisional,
  });
}

class CalibrationModel {
  /// Default along-path scatter when no replicates exist (ΔE). Roughly what
  /// phone-camera color measurements of paper strips repeat to.
  static const double defaultSigma = 2.0;

  final List<CalibrationLevel> levels;

  /// Cumulative arc length (ΔE) along the path at each level.
  final List<double> arc;

  /// Pooled along-path SD from replicates (ΔE), or null if none.
  final double? pooledSigma;

  CalibrationModel._(this.levels, this.arc, this.pooledSigma);

  /// Builds a model from individual calibration samples. Needs at least two
  /// distinct concentrations.
  factory CalibrationModel.fromSamples(List<CalibrationSample> samples) {
    // Group by concentration (to 1e-6 mg/L).
    final groups = <double, List<Vec3>>{};
    for (final s in samples) {
      final key = (s.concentration * 1e6).round() / 1e6;
      groups.putIfAbsent(key, () => []).add(s.lab);
    }
    final concs = groups.keys.toList()..sort();
    if (concs.length < 2) {
      throw ArgumentError('Need standards at two or more concentrations.');
    }
    final levels = <CalibrationLevel>[];
    for (final c in concs) {
      final labs = groups[c]!;
      final mean = labs.reduce((a, b) => a + b) / labs.length.toDouble();
      levels.add(CalibrationLevel(c, mean, labs.length));
    }
    final arc = <double>[0];
    for (var i = 1; i < levels.length; i++) {
      arc.add(arc.last + levels[i].meanLab.distanceTo(levels[i - 1].meanLab));
    }

    // Pooled along-path standard deviation from replicates.
    var ss = 0.0;
    var dof = 0;
    for (var i = 0; i < levels.length; i++) {
      final labs = groups[concs[i]]!;
      if (labs.length < 2) continue;
      final tangent = _tangent(levels, i);
      for (final l in labs) {
        final d = (l - levels[i].meanLab).dot(tangent);
        ss += d * d;
      }
      dof += labs.length - 1;
    }
    final pooled = dof > 0 ? math.sqrt(ss / dof) : null;
    return CalibrationModel._(levels, arc, pooled);
  }

  /// Unit direction of the path at level i (central difference inside,
  /// one-sided at the ends).
  static Vec3 _tangent(List<CalibrationLevel> lv, int i) {
    final a = lv[math.max(0, i - 1)].meanLab;
    final b = lv[math.min(lv.length - 1, i + 1)].meanLab;
    final d = b - a;
    final len = d.length;
    return len > 1e-9 ? d / len : const Vec3(1, 0, 0);
  }

  double get minConcentration => levels.first.concentration;
  double get maxConcentration => levels.last.concentration;
  double get totalArc => arc.last;

  /// Concentration at arc-length position u (clamped to the calibrated range).
  double concentrationAtArc(double u) {
    if (u <= 0) return minConcentration;
    if (u >= totalArc) return maxConcentration;
    var i = 0;
    while (i < arc.length - 2 && u > arc[i + 1]) {
      i++;
    }
    final seg = arc[i + 1] - arc[i];
    final t = seg > 0 ? (u - arc[i]) / seg : 0.0;
    return levels[i].concentration +
        t * (levels[i + 1].concentration - levels[i].concentration);
  }

  /// Estimates concentration for a measured Lab color.
  ///
  /// [measurementSigma] is any extra ΔE uncertainty specific to this photo
  /// (for example the pad's pixel-averaging standard error).
  ConcentrationEstimate estimate(Vec3 lab, {double measurementSigma = 0}) {
    // 1. Find the closest point on the polyline.
    var bestDist = double.infinity;
    var bestSeg = 0;
    var bestT = 0.0;
    var bestRawT = 0.0;
    for (var i = 0; i < levels.length - 1; i++) {
      final p = levels[i].meanLab;
      final d = levels[i + 1].meanLab - p;
      final len2 = d.dot(d);
      final rawT = len2 > 0 ? (lab - p).dot(d) / len2 : 0.0;
      final t = rawT.clamp(0.0, 1.0);
      final dist = lab.distanceTo(p + d * t);
      if (dist < bestDist) {
        bestDist = dist;
        bestSeg = i;
        bestT = t;
        bestRawT = rawT;
      }
    }
    final segLen = arc[bestSeg + 1] - arc[bestSeg];

    // 2. Position along the path. Beyond either end we keep the unclamped
    //    projection so we can tell "below the lowest" / "above the highest".
    var u = arc[bestSeg] + bestT * segLen;
    final below = bestSeg == 0 && bestRawT < 0;
    final above = bestSeg == levels.length - 2 && bestRawT > 1;
    if (below) u = bestRawT * segLen;
    if (above) u = arc[bestSeg] + bestRawT * segLen;

    // The off-curve distance is measured from the (possibly extended) line.
    final p = levels[bestSeg].meanLab;
    final d = levels[bestSeg + 1].meanLab - p;
    final offCurve = (below || above) ? lab.distanceTo(p + d * bestRawT) : bestDist;

    final value = concentrationAtArc(u);

    // 3. Uncertainty along the path, in ΔE.
    final provisional = pooledSigma == null;
    final sigmaCal = pooledSigma ?? defaultSigma;
    final nLocal = math.min(levels[bestSeg].n, levels[bestSeg + 1].n);
    final sigma = math.sqrt(sigmaCal * sigmaCal * (1 + 1 / nLocal) +
        measurementSigma * measurementSigma);

    // 4. Step ±1.96σ along the path and convert to concentration.
    const z = 1.96;
    final low = concentrationAtArc(u - z * sigma);
    final high = concentrationAtArc(u + z * sigma);

    final dC = levels[bestSeg + 1].concentration - levels[bestSeg].concentration;
    final sensitivity = dC > 0 ? segLen / dC : 0.0;

    return ConcentrationEstimate(
      value: value,
      low: low,
      high: high,
      belowRange: below,
      aboveRange: above,
      offCurveDeltaE: offCurve,
      sigmaDeltaE: sigma,
      sensitivity: sensitivity,
      provisional: provisional,
    );
  }
}
