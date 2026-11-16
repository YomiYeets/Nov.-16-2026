import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../analysis/analyzer.dart';
import '../analysis/card_layout.dart';
import '../analysis/image_loader.dart';
import '../app_services.dart';
import '../color/homography.dart';
import '../data/models.dart';
import 'result_screen.dart';
import 'widgets.dart';

/// Manual selection: tap the card's four corner marks (1-4), then the pad.
///
/// Pinch to zoom for accurate taps. After the corners are placed, the app
/// draws where it will sample each patch, so you can check the alignment
/// before analyzing.
class AnalyzeScreen extends StatefulWidget {
  final String photoPath;
  final MeasureRequest request;
  final double captureDelaySeconds;
  const AnalyzeScreen(
      {super.key, required this.photoPath, required this.request, required this.captureDelaySeconds});
  @override
  State<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends State<AnalyzeScreen> {
  final layout = AppServices.instance.layout;
  LoadedPhoto? _photo;
  String? _error;
  final List<Offset> _corners = []; // image pixel coords
  Offset? _pad;
  double _padRadiusMm = AppServices.instance.layout.padRadiusMm;
  bool _working = false;

  static const _prompts = [
    'Tap the center of corner mark 1 (top-left)',
    'Tap the center of corner mark 2 (top-right)',
    'Tap the center of corner mark 3 (bottom-right)',
    'Tap the center of corner mark 4 (bottom-left)',
    'Tap the center of the NITRATE pad',
  ];

  @override
  void initState() {
    super.initState();
    loadPhoto(widget.photoPath).then((ph) {
      if (mounted) setState(() => _photo = ph);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'Could not read photo: $e');
    });
  }

  Homography? get _h => _corners.length == 4 ? cardToImage(layout, _corners) : null;

  double get _padRadiusPx {
    final h = _h;
    if (h == null) return 20;
    // Pixels per mm measured at the strip slot, where the pad is.
    return h.scaleAt(layout.stripSlotMm.center) * _padRadiusMm;
  }

  int get _step => _corners.length < 4 ? _corners.length : (_pad == null ? 4 : 5);

  void _onTap(Offset imagePx) {
    setState(() {
      if (_corners.length < 4) {
        _corners.add(imagePx);
      } else {
        _pad = imagePx; // re-tapping moves the pad circle
      }
    });
  }

  void _undo() => setState(() {
        if (_pad != null) {
          _pad = null;
        } else if (_corners.isNotEmpty) {
          _corners.removeLast();
        }
      });

  Future<void> _analyze() async {
    final ph = _photo!;
    setState(() => _working = true);
    try {
      final result = analyzePhoto(
        image: ph.raster,
        layout: layout,
        fiducialsPx: _corners,
        padCenterPx: _pad!,
        padRadiusPx: _padRadiusPx,
      );
      // Keep the upright, downsized photo we analyzed (for the log).
      final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final photoFile = File(p.join(AppServices.instance.photosDir.path, 'strip_$stamp.jpg'));
      await photoFile.writeAsBytes(ph.jpeg);

      if (!mounted) return;
      if (widget.request.mode == MeasureMode.calibration) {
        await _saveCalibration(result, photoFile.path);
      } else {
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => ResultScreen(
                analysis: result,
                photoPath: photoFile.path,
                captureDelaySeconds: widget.captureDelaySeconds)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Analysis failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveCalibration(AnalysisResult r, String photoPath) async {
    final req = widget.request;
    final lab = r.padLab;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Standard ${req.standardConcentration} mg/L'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            LabSwatch(lab: lab),
            const SizedBox(width: 12),
            Text('L* ${lab.x.toStringAsFixed(1)}\n'
                'a* ${lab.y.toStringAsFixed(1)}\n'
                'b* ${lab.z.toStringAsFixed(1)}'),
          ]),
          const SizedBox(height: 8),
          Text('Card fit error: ${r.cardRmsDeltaE.toStringAsFixed(2)} ΔE'),
          for (final w in r.warnings)
            Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('⚠ $w', style: const TextStyle(color: Colors.orange))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add to curve')),
        ],
      ),
    );
    if (ok != true) return;
    await AppServices.instance.db.insertPoint(CalPointRecord(
      curveId: req.curveId!,
      concentration: req.standardConcentration!,
      lab: lab,
      cardRmsDeltaE: r.cardRmsDeltaE,
      time: DateTime.now(),
      photoPath: photoPath,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ph = _photo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select card and pad'),
        actions: [
          IconButton(onPressed: _undo, icon: const Icon(Icons.undo), tooltip: 'Undo'),
          IconButton(
              onPressed: () => setState(() {
                    _corners.clear();
                    _pad = null;
                  }),
              icon: const Icon(Icons.restart_alt),
              tooltip: 'Start over'),
        ],
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : ph == null
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Preparing photo…'),
                ]))
              : Column(children: [
                  Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.primaryContainer,
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _step < 5 ? _prompts[_step] : 'Check the boxes line up with the patches, then Analyze.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(child: _ImageTapper(photo: ph, onTap: _onTap, painterBuilder: _painter)),
                  if (_corners.length == 4)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        const Text('Pad circle'),
                        Expanded(
                          child: Slider(
                            value: _padRadiusMm,
                            min: 0.5,
                            max: 3.0,
                            divisions: 25,
                            label: '${(_padRadiusMm * 2).toStringAsFixed(1)} mm',
                            onChanged: (v) => setState(() => _padRadiusMm = v),
                          ),
                        ),
                      ]),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: (_step == 5 && !_working) ? _analyze : null,
                      icon: _working
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.science),
                      label: const Text('Analyze'),
                    ),
                  ),
                ]),
    );
  }

  CustomPainter _painter(double imageToScreen) =>
      _SelectionPainter(layout, List.of(_corners), _pad, _padRadiusPx, _h, imageToScreen);
}

/// Shows the photo in a zoomable viewer and reports taps in IMAGE pixels.
class _ImageTapper extends StatelessWidget {
  final LoadedPhoto photo;
  final void Function(Offset imagePx) onTap;
  final CustomPainter Function(double imageToScreen) painterBuilder;
  const _ImageTapper({required this.photo, required this.onTap, required this.painterBuilder});

  @override
  Widget build(BuildContext context) {
    final iw = photo.raster.width.toDouble(), ih = photo.raster.height.toDouble();
    return LayoutBuilder(builder: (context, box) {
      // Fit the image inside the available space ("contain").
      final s = [box.maxWidth / iw, box.maxHeight / ih].reduce((a, b) => a < b ? a : b);
      final w = iw * s, h = ih * s;
      return InteractiveViewer(
        maxScale: 12,
        child: Center(
          child: SizedBox(
            width: w,
            height: h,
            child: GestureDetector(
              // Positions inside the InteractiveViewer child are already in
              // un-zoomed child coordinates, so dividing by s gives pixels.
              onTapUp: (d) => onTap(d.localPosition / s),
              child: CustomPaint(
                foregroundPainter: painterBuilder(s),
                child: Image.memory(photo.jpeg, width: w, height: h, gaplessPlayback: true),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _SelectionPainter extends CustomPainter {
  final CardLayout layout;
  final List<Offset> corners;
  final Offset? pad;
  final double padRadiusPx;
  final Homography? h;
  final double s; // image px -> screen px
  _SelectionPainter(this.layout, this.corners, this.pad, this.padRadiusPx, this.h, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = Colors.cyanAccent;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < corners.length; i++) {
      final c = corners[i] * s;
      canvas.drawCircle(c, 4, dot);
      canvas.drawLine(c - const Offset(10, 0), c + const Offset(10, 0), stroke..color = Colors.cyanAccent);
      canvas.drawLine(c - const Offset(0, 10), c + const Offset(0, 10), stroke);
      final tp = TextPainter(
          text: TextSpan(
              text: '${i + 1}',
              style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.bold)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, c + const Offset(6, 6));
    }
    final hh = h;
    if (hh != null) {
      Path quad(Rect r) => Path()
        ..addPolygon([
          hh.map(r.topLeft) * s,
          hh.map(r.topRight) * s,
          hh.map(r.bottomRight) * s,
          hh.map(r.bottomLeft) * s,
        ], true);
      canvas.drawPath(quad(Offset.zero & Size(layout.widthMm, layout.heightMm)),
          stroke..color = Colors.white70);
      for (final p in layout.patches) {
        canvas.drawPath(quad(p.sampleRectMm), stroke..color = Colors.limeAccent);
      }
      canvas.drawPath(quad(layout.stripSlotMm), stroke..color = Colors.yellowAccent);
    }
    final pc = pad;
    if (pc != null) {
      canvas.drawCircle(pc * s, padRadiusPx * s, stroke..color = Colors.redAccent..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}
