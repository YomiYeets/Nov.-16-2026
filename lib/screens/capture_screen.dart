import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../analysis/card_layout.dart';
import '../app_services.dart';
import 'analyze_screen.dart';

/// Live camera with an outline showing where the card (and strip) should go.
class CaptureScreen extends StatefulWidget {
  final MeasureRequest request;
  final DateTime timerEnd;
  const CaptureScreen({super.key, required this.request, required this.timerEnd});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  CameraController? _ctrl;
  String? _error;
  bool _busy = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back,
          orElse: () => cams.first);
      final ctrl = CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await ctrl.initialize();
      // Flash off by default: a flash makes a bright hot spot (glare) on the
      // glossy pad and lights the card unevenly. Even daylight in the shade is best.
      await ctrl.setFlashMode(_flash);
      if (!mounted) return;
      setState(() => _ctrl = ctrl);
    } catch (e) {
      setState(() => _error = 'Camera unavailable: $e');
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      final delay = DateTime.now().difference(widget.timerEnd).inMilliseconds / 1000;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AnalyzeScreen(
              photoPath: file.path, request: widget.request, captureDelaySeconds: delay)));
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Capture failed: $e';
      });
    }
  }

  Future<void> _toggleFlash() async {
    _flash = _flash == FlashMode.off ? FlashMode.torch : FlashMode.off;
    await _ctrl?.setFlashMode(_flash);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Photograph card + strip'),
        actions: [
          IconButton(
              tooltip: 'Torch (not recommended)',
              onPressed: _toggleFlash,
              icon: Icon(_flash == FlashMode.off ? Icons.flash_off : Icons.flashlight_on)),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.white)))
          : c == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: Center(
                      child: CameraPreview(c,
                          child: CustomPaint(
                              painter: _GuidePainter(AppServices.instance.layout),
                              child: const SizedBox.expand())),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Fit the card inside the outline, strip in the dashed slot. '
                      'Hold the phone parallel to the card. Avoid shadows and glare.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, top: 8),
                    child: FloatingActionButton.large(
                      onPressed: _busy ? null : _shoot,
                      child: _busy
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.camera_alt, size: 40),
                    ),
                  ),
                ]),
    );
  }
}

/// Draws the card outline (to scale with the real card), the four numbered
/// corner marks and the strip slot over the camera preview.
class _GuidePainter extends CustomPainter {
  final CardLayout layout;
  _GuidePainter(this.layout);

  @override
  void paint(Canvas canvas, Size size) {
    // Card is landscape; fit 88% of the preview width (or 80% of the height).
    final scale = [size.width * 0.88 / layout.widthMm, size.height * 0.8 / layout.heightMm]
        .reduce((a, b) => a < b ? a : b);
    final w = layout.widthMm * scale, h = layout.heightMm * scale;
    final origin = Offset((size.width - w) / 2, (size.height - h) / 2);
    Offset mm(Offset p) => origin + p * scale;

    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(origin & Size(w, h), line);
    final f = layout.fiducialSizeMm * scale;
    for (var i = 0; i < layout.fiducialsMm.length; i++) {
      final c = mm(layout.fiducialsMm[i]);
      canvas.drawRect(Rect.fromCenter(center: c, width: f, height: f), line);
      final tp = TextPainter(
          text: TextSpan(
              text: '${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 14)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, c + Offset(f * 0.7, f * 0.2));
    }
    // Strip slot as a dashed rectangle.
    final slot = layout.stripSlotMm;
    final r = Rect.fromPoints(mm(slot.topLeft), mm(slot.bottomRight));
    final dash = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2;
    void dashed(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 12) {
        canvas.drawLine(a + dir * d, a + dir * (d + 6).clamp(0, len), dash);
      }
    }

    dashed(r.topLeft, r.topRight);
    dashed(r.topRight, r.bottomRight);
    dashed(r.bottomRight, r.bottomLeft);
    dashed(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => false;
}
