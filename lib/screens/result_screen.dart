import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';

import '../analysis/analyzer.dart';
import '../app_services.dart';
import '../color/calibration_curve.dart';
import '../data/models.dart';
import 'widgets.dart';

class ResultScreen extends StatefulWidget {
  final AnalysisResult analysis;
  final String photoPath;
  final double captureDelaySeconds;
  const ResultScreen(
      {super.key, required this.analysis, required this.photoPath, required this.captureDelaySeconds});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final s = AppServices.instance;
  CurveRecord? _curve;
  CalibrationModel? _model;
  ConcentrationEstimate? _est;
  bool _loading = true;
  Position? _pos;
  String _gpsStatus = 'Getting location…';
  List<String> _sites = [];
  String _defaultSite = '';
  TextEditingController? _siteField;
  String get _siteText => _siteField?.text ?? _defaultSite;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _locate();
  }

  Future<void> _load() async {
    final id = s.activeCurveId;
    if (id != null) {
      _curve = await s.db.curve(id);
      _model = await s.db.model(id);
      _est = _model?.estimate(widget.analysis.padLab,
          measurementSigma: widget.analysis.padSigmaDeltaE);
    }
    _sites = await s.db.siteNames();
    if (_sites.isNotEmpty) _defaultSite = _sites.first;
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _gpsStatus = 'Location services are off');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() => _gpsStatus = 'Location permission denied');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)));
      if (mounted) {
        setState(() {
          _pos = pos;
          _gpsStatus = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} '
              '(±${pos.accuracy.toStringAsFixed(0)} m)';
        });
      }
    } on TimeoutException {
      if (mounted) setState(() => _gpsStatus = 'No GPS fix (timed out)');
    } catch (e) {
      if (mounted) setState(() => _gpsStatus = 'Location unavailable: $e');
    }
  }

  Future<void> _save() async {
    final e = _est!;
    final a = widget.analysis;
    if (_siteText.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a site name')));
      return;
    }
    await s.db.insertReading(ReadingRecord(
      time: DateTime.now(),
      site: _siteText.trim(),
      latitude: _pos?.latitude,
      longitude: _pos?.longitude,
      gpsAccuracyM: _pos?.accuracy,
      no3n: e.value,
      low: e.low,
      high: e.high,
      belowRange: e.belowRange,
      aboveRange: e.aboveRange,
      provisional: e.provisional,
      lab: a.padLab,
      cardRmsDeltaE: a.cardRmsDeltaE,
      offCurveDeltaE: e.offCurveDeltaE,
      curveId: _curve?.id,
      curveName: _curve?.name ?? '',
      devTimeSeconds: s.devTimeSeconds,
      captureDelaySeconds: widget.captureDelaySeconds,
      photoPath: widget.photoPath,
      notes: _notes.text.trim(),
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = widget.analysis;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final e = _est;
    final warnings = [...a.warnings];
    if (e != null) {
      if (e.offCurveDeltaE > 4 && e.offCurveDeltaE > 3 * e.sigmaDeltaE) {
        warnings.add('The pad color is ${e.offCurveDeltaE.toStringAsFixed(1)} ΔE away from the '
            'calibration curve. The strip lot, timing or lighting may not match the calibration.');
      }
      if (e.provisional) {
        warnings.add('Confidence range is provisional: add repeat strips for each standard '
            'to measure the real scatter.');
      }
      if (widget.captureDelaySeconds > 30) {
        warnings.add('Photo taken ${widget.captureDelaySeconds.toStringAsFixed(0)} s after the timer. '
            'The pad may have kept developing.');
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (e == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  _curve == null
                      ? 'No calibration curve is selected. Create one under Calibration curves.'
                      : 'Curve "${_curve!.name}" needs standards at two or more concentrations.',
                  style: t.titleMedium),
            ),
          )
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            LabSwatch(lab: a.padLab, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${formatConc(e.value, below: e.belowRange, above: e.aboveRange)} mg/L',
                    style: t.displaySmall?.copyWith(fontWeight: FontWeight.bold)),
                Text('nitrate-N (NO3-N)', style: t.bodyMedium),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text('95% range: ${e.low.toStringAsFixed(1)} – ${e.high.toStringAsFixed(1)} mg/L NO3-N',
              style: t.titleMedium),
          Text('As nitrate ion: ${formatConc(e.value * no3PerNo3N, below: e.belowRange, above: e.aboveRange)} mg/L NO3- '
              '(${(e.low * no3PerNo3N).toStringAsFixed(0)}–${(e.high * no3PerNo3N).toStringAsFixed(0)})'),
          if (e.value >= 10 && !e.belowRange)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('At or above the US EPA drinking-water limit (10 mg/L NO3-N).',
                  style: TextStyle(color: Colors.red)),
            ),
        ],
        for (final w in warnings)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('⚠ $w', style: const TextStyle(color: Colors.orange))),
        const Divider(height: 32),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _defaultSite),
          optionsBuilder: (v) => _sites.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
          fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
            _siteField = ctrl;
            return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(labelText: 'Site name', border: OutlineInputBorder()));
          },
        ),
        const SizedBox(height: 12),
        TextField(
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(Icons.place_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text(_gpsStatus)),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: e == null ? null : _save,
            icon: const Icon(Icons.save),
            label: const Text('Save to log')),
        const SizedBox(height: 16),
        ExpansionTile(title: const Text('Measurement details'), children: [
          ListTile(dense: true, title: const Text('Pad color (corrected)'), subtitle: Text(labText(a.padLab))),
          ListTile(
              dense: true,
              title: const Text('Card fit error (RMS)'),
              subtitle: Text('${a.cardRmsDeltaE.toStringAsFixed(2)} ΔE  (under 2 is good)')),
          if (e != null) ...[
            ListTile(
                dense: true,
                title: const Text('Distance from calibration curve'),
                subtitle: Text('${e.offCurveDeltaE.toStringAsFixed(2)} ΔE')),
            ListTile(
                dense: true,
                title: const Text('Color sensitivity here'),
                subtitle: Text('${e.sensitivity.toStringAsFixed(2)} ΔE per mg/L')),
            ListTile(
                dense: true,
                title: const Text('Uncertainty used (σ along curve)'),
                subtitle: Text('${e.sigmaDeltaE.toStringAsFixed(2)} ΔE${e.provisional ? ' (default)' : ''}')),
            if (_model != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  for (final l in _model!.levels)
                    Expanded(
                      child: Column(children: [
                        LabSwatch(lab: l.meanLab, size: 36),
                        Text(l.concentration.toStringAsFixed(0), style: t.bodySmall),
                      ]),
                    ),
                ]),
              ),
          ],
          ListTile(
              dense: true,
              title: const Text('Capture delay after timer'),
              subtitle: Text('${widget.captureDelaySeconds.toStringAsFixed(0)} s')),
        ]),
      ]),
    );
  }
}
