import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../analysis/card_layout.dart';
import '../app_services.dart';

/// Preview of the reference card and a button to share/print the PDF.
class CardScreen extends StatelessWidget {
  const CardScreen({super.key});

  Future<void> _sharePdf() async {
    final data = await rootBundle.load('assets/reference_card.pdf');
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, 'nitrate_reference_card.pdf'));
    await f.writeAsBytes(data.buffer.asUint8List());
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], subject: 'Reference card'));
  }

  @override
  Widget build(BuildContext context) {
    final layout = AppServices.instance.layout;
    return Scaffold(
      appBar: AppBar(title: const Text('Reference card')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AspectRatio(
          aspectRatio: layout.widthMm / layout.heightMm,
          child: CustomPaint(painter: CardPreviewPainter(layout)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: _sharePdf, icon: const Icon(Icons.print), label: const Text('Share / print PDF')),
        const SizedBox(height: 16),
        const Text(
          'Printing tips\n'
          '• Print at 100% / "Actual size". Do not use "Fit to page".\n'
          '• Use matte white paper. A laser printer is the most stable choice.\n'
          '• Check the ruler on the page measures 50 mm.\n'
          '• Use the SAME printed card for calibration and readings. If you reprint, recalibrate.\n'
          '• Keep it dry and out of sunlight (inks fade). A matte laminating pouch is fine; '
          'glossy lamination causes glare.',
        ),
      ]),
    );
  }
}

/// Draws the card from the layout (the same data the PDF is made from).
class CardPreviewPainter extends CustomPainter {
  final CardLayout layout;
  CardPreviewPainter(this.layout);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / layout.widthMm;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Colors.black26
          ..style = PaintingStyle.stroke);
    for (final f in layout.fiducialsMm) {
      final w = layout.fiducialSizeMm * s;
      canvas.drawRect(Rect.fromCenter(center: f * s, width: w, height: w), Paint()..color = Colors.black);
    }
    for (final pt in layout.patches) {
      final r = pt.rectMm;
      canvas.drawRect(Rect.fromLTWH(r.left * s, r.top * s, r.width * s, r.height * s),
          Paint()..color = Color.fromARGB(255, pt.srgb8[0], pt.srgb8[1], pt.srgb8[2]));
    }
    final slot = layout.stripSlotMm;
    canvas.drawRect(
        Rect.fromLTWH(slot.left * s, slot.top * s, slot.width * s, slot.height * s),
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
