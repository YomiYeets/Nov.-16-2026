// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nitrate_reader/analysis/analyzer.dart';
import 'package:nitrate_reader/analysis/card_layout.dart';
import 'package:nitrate_reader/color/calibration_curve.dart';
import 'package:nitrate_reader/color/color_correction.dart';
import 'package:nitrate_reader/color/color_space.dart';
import 'package:nitrate_reader/color/homography.dart';
import 'package:nitrate_reader/color/sampling.dart';
import 'package:nitrate_reader/color/vec3.dart';

/// A made-up "camera": a color cast + cross-talk matrix, flare, then a
/// non-linear per-channel response. The correction must undo all of it.
Vec3 fakeCamera(Vec3 trueLinear) {
  final m = [
    [0.80, 0.12, 0.02],
    [0.05, 0.70, 0.05],
    [0.02, 0.10, 0.50], // strong blue loss = warm/yellow light
  ];
  final v = [
    for (final r in m) r[0] * trueLinear.x + r[1] * trueLinear.y + r[2] * trueLinear.z + 0.01
  ];
  double resp(double x) => math.pow(x.clamp(0, 1), 0.85).toDouble();
  return Vec3(resp(v[0]), resp(v[1]), resp(v[2]));
}

void main() {
  group('color space', () {
    test('sRGB white is L*=100, a*=b*=0', () {
      final lab = linearRgbToLab(const Vec3(1, 1, 1));
      expect(lab.x, closeTo(100, 0.01));
      expect(lab.y, closeTo(0, 0.01));
      expect(lab.z, closeTo(0, 0.01));
    });
    test('sRGB red matches published Lab (53.24, 80.09, 67.20)', () {
      final lab = linearRgbToLab(srgb8ToLinear(255, 0, 0));
      expect(lab.x, closeTo(53.24, 0.05));
      expect(lab.y, closeTo(80.09, 0.05));
      expect(lab.z, closeTo(67.20, 0.05));
    });
    test('Lab round trip', () {
      const rgb = Vec3(0.3, 0.1, 0.25);
      final back = labToLinearRgb(linearRgbToLab(rgb));
      expect(back.distanceTo(rgb), lessThan(1e-6));
    });
    test('mid-gray code 128 is ~21.6% light', () {
      expect(srgb8ToLinearLut[128], closeTo(0.2158, 0.001));
    });
  });

  test('homography maps corner points and is projective', () {
    final src = [const Offset(0, 0), const Offset(100, 0), const Offset(100, 70), const Offset(0, 70)];
    final dst = [const Offset(120, 80), const Offset(900, 140), const Offset(860, 700), const Offset(100, 620)];
    final h = Homography.fromPoints(src, dst);
    for (var i = 0; i < 4; i++) {
      expect((h.map(src[i]) - dst[i]).distance, lessThan(1e-6));
    }
    // Inverse composed with forward is the identity.
    final inv = Homography.fromPoints(dst, src);
    final p = inv.map(h.map(const Offset(37, 21)));
    expect((p - const Offset(37, 21)).distance, lessThan(1e-6));
  });

  test('color correction undoes a strong synthetic cast', () {
    final layout = CardLayout.fromJson(File('assets/card_layout.json').readAsStringSync());
    final obs = [
      for (final p in layout.patches)
        PatchObservation(fakeCamera(p.referenceLinear), p.referenceLinear,
            isGray: p.kind == PatchKind.gray, weight: p.kind == PatchKind.pink ? 3 : 1)
    ];
    final cc = ColorCorrection.fit(obs);
    expect(cc.rmsDeltaE, lessThan(2.0));
    // A pad-like magenta that is NOT one of the patches.
    final truth = srgb8ToLinear(214, 120, 165);
    final corrected = cc.apply(fakeCamera(truth));
    final de = deltaE76(linearRgbToLab(corrected), linearRgbToLab(truth));
    final uncorrectedDe = deltaE76(linearRgbToLab(fakeCamera(truth)), linearRgbToLab(truth));
    expect(uncorrectedDe, greaterThan(10));
    print('cast test: uncorrected ΔE=${uncorrectedDe.toStringAsFixed(1)} corrected ΔE=${de.toStringAsFixed(2)} cardRMS=${cc.rmsDeltaE.toStringAsFixed(2)}');
    expect(de, lessThan(2.0));
  });

  group('calibration curve', () {
    // Synthetic path from near-white to magenta.
    Vec3 labFor(double c) {
      final t = math.sqrt(c / 50); // fast change at low c, slower at high c
      return Vec3(94 - 40 * t, 2 + 50 * t, -1 - 8 * t);
    }

    final standards = [0.0, 5.0, 10.0, 20.0, 50.0];

    test('interpolates between standards and reports the range', () {
      final model = CalibrationModel.fromSamples(
          [for (final c in standards) CalibrationSample(c, labFor(c))]);
      // Halfway along the segment 10..20 in Lab gives exactly 15.
      final mid = (labFor(10) + labFor(20)) / 2;
      final e = model.estimate(mid);
      expect(e.value, closeTo(15, 1e-6));
      expect(e.offCurveDeltaE, lessThan(1e-6));
      expect(e.provisional, isTrue);
      expect(e.low, lessThan(15));
      expect(e.high, greaterThan(15));
      expect(e.belowRange || e.aboveRange, isFalse);
    });

    test('flags off-curve and out-of-range colors', () {
      final model = CalibrationModel.fromSamples(
          [for (final c in standards) CalibrationSample(c, labFor(c))]);
      final beyond = labFor(50) + (labFor(50) - labFor(20)) * 0.5;
      expect(model.estimate(beyond).aboveRange, isTrue);
      expect(model.estimate(beyond).value, 50);
      final off = labFor(10) + const Vec3(0, 0, 15);
      expect(model.estimate(off).offCurveDeltaE, closeTo(15, 1.5));
    });

    test('replicates give a pooled sigma', () {
      final rnd = math.Random(1);
      final samples = <CalibrationSample>[];
      for (final c in standards) {
        for (var k = 0; k < 3; k++) {
          final n = Vec3(rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.5, rnd.nextDouble() - 0.5) * 2;
          samples.add(CalibrationSample(c, labFor(c) + n));
        }
      }
      final model = CalibrationModel.fromSamples(samples);
      expect(model.pooledSigma, isNotNull);
      expect(model.pooledSigma!, lessThan(1.5));
      final e = model.estimate(labFor(7));
      expect(e.provisional, isFalse);
      expect(e.value, closeTo(7, 1.5));
      expect(e.low, lessThanOrEqualTo(e.value));
      expect(e.high, greaterThanOrEqualTo(e.value));
    });
  });

  test('end to end: synthetic photo of card + pad under a color cast', () {
    final layout = CardLayout.fromJson(File('assets/card_layout.json').readAsStringSync());
    const w = 900, h = 700;
    final cornersPx = [const Offset(110, 90), const Offset(800, 130), const Offset(780, 610), const Offset(90, 580)];
    final cardToPx = Homography.fromPoints(layout.fiducialsMm, cornersPx);
    final pxToCard = Homography.fromPoints(cornersPx, layout.fiducialsMm);
    final padTruth = srgb8ToLinear(220, 140, 180);
    const padMm = Offset(50, 52.5);

    final data = Uint8List(w * h * 3);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final mm = pxToCard.map(Offset(x.toDouble(), y.toDouble()));
        Vec3 c = srgb8ToLinear(245, 245, 245); // paper
        for (final p in layout.patches) {
          if (p.rectMm.contains(mm)) c = p.referenceLinear;
        }
        if ((mm - padMm).distance < 2.5) c = padTruth;
        final s = linearVecToSrgb(fakeCamera(c));
        final i = (y * w + x) * 3;
        data[i] = (s.x.clamp(0, 1) * 255).round();
        data[i + 1] = (s.y.clamp(0, 1) * 255).round();
        data[i + 2] = (s.z.clamp(0, 1) * 255).round();
      }
    }
    final raster = RgbRaster(w, h, data);
    final padPx = cardToPx.map(padMm);
    final r = analyzePhoto(
      image: raster,
      layout: layout,
      fiducialsPx: cornersPx,
      padCenterPx: padPx,
      padRadiusPx: cardToPx.scaleAt(padMm) * layout.padRadiusMm,
    );
    final de = deltaE76(r.padLab, linearRgbToLab(padTruth));
    print('e2e: pad ΔE=${de.toStringAsFixed(2)} cardRMS=${r.cardRmsDeltaE.toStringAsFixed(2)} warnings=${r.warnings}');
    expect(r.cardRmsDeltaE, lessThan(2.5));
    expect(de, lessThan(2.5), reason: 'pad ΔE vs truth = $de');
  });
}
