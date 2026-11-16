import 'dart:convert';
import 'dart:ui' show Offset, Rect;

import '../color/color_space.dart';
import '../color/vec3.dart';

enum PatchKind { gray, pink, anchor }

class CardPatch {
  final String id, name;
  final PatchKind kind;
  final Rect rectMm;
  final List<int> srgb8;

  /// Optional measured Lab of the printed patch (overrides [srgb8]).
  final Vec3? measuredLab;

  CardPatch(this.id, this.name, this.kind, this.rectMm, this.srgb8, this.measuredLab);

  /// The known color the correction should map this patch to, linear RGB.
  ///
  /// NOTE ON ACCURACY OF THESE VALUES: your printer will not reproduce the
  /// nominal sRGB values exactly. That is fine as long as you use the SAME
  /// printed card for calibration and for readings. Any error in the
  /// reference values becomes a fixed distortion of "corrected" color space
  /// that is the same in every photo, and the calibration curve, which is
  /// built in that same space, absorbs it. You only need measured values
  /// (the optional "lab" field) if you want to share calibration curves
  /// between different printed cards.
  Vec3 get referenceLinear => measuredLab != null
      ? labToLinearRgb(measuredLab!)
      : srgb8ToLinear(srgb8[0], srgb8[1], srgb8[2]);

  Vec3 get referenceLab => measuredLab ?? linearRgbToLab(referenceLinear);

  /// The inner 60% of the patch: we stay away from the edges so slightly
  /// mis-tapped corners or printer bleed don't contaminate the sample.
  Rect get sampleRectMm => Rect.fromCenter(
      center: rectMm.center, width: rectMm.width * 0.6, height: rectMm.height * 0.6);
}

class CardLayout {
  final int version;
  final double widthMm, heightMm, fiducialSizeMm, padRadiusMm;
  final List<Offset> fiducialsMm; // marks 1..4: TL, TR, BR, BL
  final List<CardPatch> patches;
  final Rect stripSlotMm;

  CardLayout._(this.version, this.widthMm, this.heightMm, this.fiducialSizeMm,
      this.padRadiusMm, this.fiducialsMm, this.patches, this.stripSlotMm);

  factory CardLayout.fromJson(String source) {
    final j = jsonDecode(source) as Map<String, dynamic>;
    double d(Object? v) => (v as num).toDouble();
    final patches = <CardPatch>[];
    for (final p in j['patches'] as List) {
      final m = p as Map<String, dynamic>;
      patches.add(CardPatch(
        m['id'] as String,
        m['name'] as String,
        PatchKind.values.byName(m['kind'] as String),
        Rect.fromLTWH(d(m['x']), d(m['y']), d(m['w']), d(m['h'])),
        (m['srgb'] as List).map((e) => (e as num).toInt()).toList(),
        m['lab'] == null ? null : Vec3.fromList((m['lab'] as List).cast<num>()),
      ));
    }
    final s = j['stripSlot'] as Map<String, dynamic>;
    return CardLayout._(
      (j['version'] as num).toInt(),
      d(j['width']),
      d(j['height']),
      d(j['fiducialSize']),
      d(j['padRadiusMm']),
      [for (final f in j['fiducials'] as List) Offset(d((f as List)[0]), d(f[1]))],
      patches,
      Rect.fromLTWH(d(s['x']), d(s['y']), d(s['w']), d(s['h'])),
    );
  }
}
