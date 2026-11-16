// Measuring the average color of a region of the photo.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'color_space.dart';
import 'homography.dart';
import 'vec3.dart';

/// A plain 8-bit RGB raster (3 bytes per pixel, row-major). Kept independent
/// of any image library so the math can be tested with synthetic images.
class RgbRaster {
  final int width, height;
  final Uint8List data;
  RgbRaster(this.width, this.height, this.data)
      : assert(data.length == width * height * 3);

  /// Linear-light color of the pixel nearest to (x, y), or null if outside.
  Vec3? linearAt(double x, double y) {
    final xi = x.round(), yi = y.round();
    if (xi < 0 || yi < 0 || xi >= width || yi >= height) return null;
    final i = (yi * width + xi) * 3;
    return srgb8ToLinear(data[i], data[i + 1], data[i + 2]);
  }

  /// Raw 8-bit values at (x, y), for clipping checks.
  List<int>? rawAt(double x, double y) {
    final xi = x.round(), yi = y.round();
    if (xi < 0 || yi < 0 || xi >= width || yi >= height) return null;
    final i = (yi * width + xi) * 3;
    return [data[i], data[i + 1], data[i + 2]];
  }
}

/// Summary statistics of a sampled region, all in LINEAR RGB.
class RegionStats {
  /// Trimmed mean color.
  final Vec3 mean;

  /// Per-channel standard deviation of the kept pixels.
  final Vec3 sd;

  /// Number of pixels kept after trimming.
  final int n;

  /// Fraction of sampled pixels with any channel at 0 or 255 (clipped).
  final double clippedFraction;

  const RegionStats(this.mean, this.sd, this.n, this.clippedFraction);

  /// Standard error of the mean, per channel: sd / sqrt(n). This is how
  /// uncertain the *average* is, which is far smaller than the pixel spread.
  Vec3 get standardError => n > 0 ? sd / math.sqrt(n.toDouble()) : sd;
}

/// Robust average of a set of linear-RGB samples.
///
/// Why average in linear RGB: averaging is a physical mixing of light, and
/// light mixes linearly. Averaging encoded sRGB values would bias the result
/// towards darker colors.
///
/// Why "trimmed": a pad can have a specular glint (too bright), an edge of the
/// plastic strip, or a speck of sediment (too dark). We sort samples by
/// luminance and drop the brightest and darkest [trim] fraction before
/// averaging. With trim = 0.1 up to 10% of pixels at each end can be junk
/// without affecting the result.
RegionStats robustMean(List<Vec3> samples, List<bool> clipped, {double trim = 0.1}) {
  if (samples.isEmpty) return const RegionStats(Vec3.zero, Vec3.zero, 0, 0);
  final idx = List<int>.generate(samples.length, (i) => i);
  final lum = samples.map(luminance).toList();
  idx.sort((a, b) => lum[a].compareTo(lum[b]));
  final drop = (samples.length * trim).floor();
  final kept = idx.sublist(drop, samples.length - drop);
  var sum = Vec3.zero;
  for (final i in kept) {
    sum = sum + samples[i];
  }
  final mean = sum / kept.length.toDouble();
  var sx = 0.0, sy = 0.0, sz = 0.0;
  for (final i in kept) {
    final d = samples[i] - mean;
    sx += d.x * d.x;
    sy += d.y * d.y;
    sz += d.z * d.z;
  }
  final denom = math.max(1, kept.length - 1).toDouble();
  final sd = Vec3(math.sqrt(sx / denom), math.sqrt(sy / denom), math.sqrt(sz / denom));
  final clippedFrac = clipped.where((c) => c).length / clipped.length;
  return RegionStats(mean, sd, kept.length, clippedFrac);
}

bool _isClipped(List<int> raw) => raw.any((v) => v <= 1 || v >= 254);

/// Samples every pixel inside a circle (used for the test pad).
RegionStats sampleCircle(RgbRaster img, Offset center, double radius) {
  final samples = <Vec3>[];
  final clipped = <bool>[];
  final r2 = radius * radius;
  for (var y = (center.dy - radius).floor(); y <= (center.dy + radius).ceil(); y++) {
    for (var x = (center.dx - radius).floor(); x <= (center.dx + radius).ceil(); x++) {
      final dx = x - center.dx, dy = y - center.dy;
      if (dx * dx + dy * dy > r2) continue;
      final c = img.linearAt(x.toDouble(), y.toDouble());
      if (c == null) continue;
      samples.add(c);
      clipped.add(_isClipped(img.rawAt(x.toDouble(), y.toDouble())!));
    }
  }
  return robustMean(samples, clipped);
}

/// Samples a rectangle given in CARD millimetres, mapped into the photo
/// through the homography. We step over a regular grid in card space, so the
/// samples follow the perspective-distorted patch exactly.
RegionStats sampleCardRect(RgbRaster img, Homography h,
    double xMm, double yMm, double wMm, double hMm, {int grid = 24}) {
  final samples = <Vec3>[];
  final clipped = <bool>[];
  for (var j = 0; j < grid; j++) {
    for (var i = 0; i < grid; i++) {
      final p = h.map(Offset(xMm + wMm * (i + 0.5) / grid, yMm + hMm * (j + 0.5) / grid));
      final c = img.linearAt(p.dx, p.dy);
      if (c == null) continue;
      samples.add(c);
      clipped.add(_isClipped(img.rawAt(p.dx, p.dy)!));
    }
  }
  return robustMean(samples, clipped);
}
