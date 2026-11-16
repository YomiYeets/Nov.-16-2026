// Perspective mapping between the printed card (millimetres) and the photo
// (pixels).
//
// The phone is never held perfectly square to the card, so a rectangle on the
// card shows up as a general quadrilateral in the photo. A *homography* is
// the 3x3 matrix H that describes that perspective projection of a flat
// surface:
//
//     [u']   [h0 h1 h2] [x]
//     [v'] = [h3 h4 h5] [y]        pixel = (u'/w', v'/w')
//     [w']   [h6 h7  1] [1]
//
// It has 8 unknowns. Each point correspondence (x,y) -> (u,v) gives two linear
// equations, so the four tapped corner marks determine H exactly. Once we have
// H, we can find where *any* patch of the known card layout lands in the photo.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'linalg.dart';

class Homography {
  /// Row-major 3x3 matrix, h[8] == 1.
  final List<double> h;
  const Homography(this.h);

  /// Builds H from exactly four correspondences src[i] -> dst[i].
  factory Homography.fromPoints(List<Offset> src, List<Offset> dst) {
    assert(src.length == 4 && dst.length == 4);
    final a = <List<double>>[];
    final b = <double>[];
    for (var i = 0; i < 4; i++) {
      final x = src[i].dx, y = src[i].dy, u = dst[i].dx, v = dst[i].dy;
      // u = (h0 x + h1 y + h2) / (h6 x + h7 y + 1)  rearranged to be linear:
      a.add([x, y, 1, 0, 0, 0, -u * x, -u * y]);
      b.add(u);
      // v = (h3 x + h4 y + h5) / (h6 x + h7 y + 1)
      a.add([0, 0, 0, x, y, 1, -v * x, -v * y]);
      b.add(v);
    }
    final s = solveLinear(a, b);
    return Homography([...s, 1.0]);
  }

  Offset map(Offset p) {
    final w = h[6] * p.dx + h[7] * p.dy + h[8];
    return Offset(
      (h[0] * p.dx + h[1] * p.dy + h[2]) / w,
      (h[3] * p.dx + h[4] * p.dy + h[5]) / w,
    );
  }

  /// Approximate pixels-per-millimetre near card point [p] (the geometric
  /// mean of the local x and y scale).
  double scaleAt(Offset p) {
    final o = map(p);
    final dx = (map(p + const Offset(1, 0)) - o).distance;
    final dy = (map(p + const Offset(0, 1)) - o).distance;
    return math.sqrt(dx * dy);
  }
}
