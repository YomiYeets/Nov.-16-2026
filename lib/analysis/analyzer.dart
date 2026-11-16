// The full measurement pipeline for one photo:
//
//   tapped corner marks --(homography)--> where each patch is in the photo
//   sample each patch (linear RGB)    --> fit ColorCorrection
//   sample the pad (linear RGB)       --> apply correction --> CIELAB
//
// Everything here is pure Dart (no Flutter widgets), so it can be unit-tested
// with synthetic images and later reused by automatic card detection, which
// will only have to supply the four corner points.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../color/color_correction.dart';
import '../color/color_space.dart';
import '../color/homography.dart';
import '../color/sampling.dart';
import '../color/vec3.dart';
import 'card_layout.dart';

class PatchResult {
  final CardPatch patch;
  final RegionStats stats;
  final bool excluded;
  final double deltaE; // after correction, vs reference (NaN if excluded)
  const PatchResult(this.patch, this.stats, this.excluded, this.deltaE);
}

class AnalysisResult {
  final Vec3 padRawLinear;
  final Vec3 padCorrectedLinear;
  final Vec3 padLab;

  /// Pixel-averaging uncertainty of the pad mean, expressed as ΔE.
  final double padSigmaDeltaE;
  final double cardRmsDeltaE;
  final List<PatchResult> patches;
  final List<String> warnings;
  final Homography homography;

  const AnalysisResult({
    required this.padRawLinear,
    required this.padCorrectedLinear,
    required this.padLab,
    required this.padSigmaDeltaE,
    required this.cardRmsDeltaE,
    required this.patches,
    required this.warnings,
    required this.homography,
  });
}

/// Weights for the color-matrix fit. Pinks resemble the pad, so being right
/// there matters most.
double _weightFor(PatchKind k) => switch (k) {
      PatchKind.pink => 3.0,
      PatchKind.gray => 1.0,
      PatchKind.anchor => 1.0,
    };

Homography cardToImage(CardLayout layout, List<Offset> fiducialsPx) =>
    Homography.fromPoints(layout.fiducialsMm, fiducialsPx);

AnalysisResult analyzePhoto({
  required RgbRaster image,
  required CardLayout layout,
  required List<Offset> fiducialsPx,
  required Offset padCenterPx,
  required double padRadiusPx,
}) {
  final warnings = <String>[];
  final h = cardToImage(layout, fiducialsPx);

  // 1. Measure every patch.
  final measured = <(CardPatch, RegionStats, bool)>[];
  for (final p in layout.patches) {
    final r = p.sampleRectMm;
    final st = sampleCardRect(image, h, r.left, r.top, r.width, r.height);
    // A clipped patch (pure white or black pixels) has lost information:
    // the camera can't tell us how bright it really was. Leave it out.
    final excluded = st.n == 0 || st.clippedFraction > 0.2;
    measured.add((p, st, excluded));
  }
  final excludedNames = measured.where((m) => m.$3).map((m) => m.$1.name).toList();
  if (excludedNames.isNotEmpty) {
    warnings.add('Patches ignored (over/under-exposed or off-image): '
        '${excludedNames.join(', ')}.');
  }

  // 2. Fit the color correction on the usable patches.
  final obs = [
    for (final m in measured)
      if (!m.$3)
        PatchObservation(m.$2.mean, m.$1.referenceLinear,
            isGray: m.$1.kind == PatchKind.gray, weight: _weightFor(m.$1.kind))
  ];
  final ColorCorrection cc;
  if (obs.length >= 6) {
    cc = ColorCorrection.fit(obs);
  } else {
    warnings.add('Too few usable card patches; colors are NOT corrected.');
    cc = ColorCorrection.identity();
  }

  final patchResults = <PatchResult>[];
  for (final m in measured) {
    final de = m.$3
        ? double.nan
        : deltaE76(linearRgbToLab(cc.apply(m.$2.mean)), m.$1.referenceLab);
    patchResults.add(PatchResult(m.$1, m.$2, m.$3, de));
  }
  if (cc.rmsDeltaE > 3) {
    warnings.add('Card fit error is high (${cc.rmsDeltaE.toStringAsFixed(1)} ΔE). '
        'Check for glare or shadows on the card and that the corner marks were tapped accurately.');
  }

  // 3. Measure the pad and apply the correction.
  final pad = sampleCircle(image, padCenterPx, padRadiusPx);
  if (pad.n < 20) warnings.add('Very few pad pixels sampled; enlarge the pad circle.');
  if (pad.clippedFraction > 0.05) {
    warnings.add('Part of the pad is over-exposed (glare). Tilt the card or move away from direct light.');
  }
  final corrected = cc.apply(pad.mean);
  final lab = linearRgbToLab(corrected);

  // Pixel noise of the mean, as ΔE: shift the mean by one standard error and
  // see how far its Lab color moves. (Usually well under 0.5 ΔE.)
  final se = pad.standardError;
  final padSigma = deltaE76(linearRgbToLab(cc.apply(pad.mean + se)), lab) / math.sqrt(3);

  // Uneven pad color usually means the pad is not evenly wetted, or the circle
  // overlaps the strip's plastic backing.
  final padSpread = deltaE76(linearRgbToLab(cc.apply(pad.mean + pad.sd)), lab);
  if (padSpread > 12) {
    warnings.add('Pad color is uneven (spread ${padSpread.toStringAsFixed(0)} ΔE). '
        'Make sure the circle is inside the pad.');
  }

  return AnalysisResult(
    padRawLinear: pad.mean,
    padCorrectedLinear: corrected,
    padLab: lab,
    padSigmaDeltaE: padSigma,
    cardRmsDeltaE: cc.rmsDeltaE,
    patches: patchResults,
    warnings: warnings,
    homography: h,
  );
}
