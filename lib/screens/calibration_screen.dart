import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../color/calibration_curve.dart';
import '../data/models.dart';
import 'timer_screen.dart';
import 'widgets.dart';

/// Lists calibration curves (one per strip lot) and lets you pick the active one.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});
  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  final s = AppServices.instance;
  List<CurveRecord> _curves = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final c = await s.db.curves();
    if (mounted) setState(() => _curves = c);
  }

  Future<void> _newCurve() async {
    final name = TextEditingController();
    final lot = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New calibration curve'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name (e.g. "Hach bottle Nov 2026")')),
          TextField(controller: lot, decoration: const InputDecoration(labelText: 'Strip lot / expiry (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final id = await s.db.insertCurve(
        CurveRecord(name: name.text.trim(), lot: lot.text.trim(), created: DateTime.now()));
    s.activeCurveId ??= id;
    await _load();
    if (mounted) _open(_curves.firstWhere((c) => c.id == id));
  }

  Future<void> _open(CurveRecord c) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CurveDetailScreen(curve: c)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final active = s.activeCurveId;
    return Scaffold(
      appBar: AppBar(title: const Text('Calibration curves')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _newCurve, icon: const Icon(Icons.add), label: const Text('New curve')),
      body: _curves.isEmpty
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                  'No curves yet.\n\nCreate one per box/lot of strips, then photograph '
                  'strips dipped in standards (e.g. 0, 5, 10, 20, 50 mg/L NO3-N). '
                  'Two or three strips per standard give a real confidence range.',
                  textAlign: TextAlign.center),
            ))
          : RadioGroup<int>(
              groupValue: active,
              onChanged: (v) => setState(() => s.activeCurveId = v),
              child: ListView(children: [
                for (final c in _curves)
                  ListTile(
                    leading: Radio<int>(value: c.id!),
                    title: Text(c.name),
                    subtitle: Text([if (c.lot.isNotEmpty) 'Lot ${c.lot}', 'Created ${c.created.toLocal().toString().substring(0, 10)}'].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(c),
                  ),
              ]),
            ),
    );
  }
}

/// Shows the standards measured for one curve and adds new ones.
class CurveDetailScreen extends StatefulWidget {
  final CurveRecord curve;
  const CurveDetailScreen({super.key, required this.curve});
  @override
  State<CurveDetailScreen> createState() => _CurveDetailScreenState();
}

class _CurveDetailScreenState extends State<CurveDetailScreen> {
  final s = AppServices.instance;
  static const standardLevels = [0.0, 5.0, 10.0, 20.0, 50.0];
  List<CalPointRecord> _points = [];
  CalibrationModel? _model;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts = await s.db.points(widget.curve.id!);
    final m = await s.db.model(widget.curve.id!);
    if (mounted) {
      setState(() {
        _points = pts;
        _model = m;
      });
    }
  }

  Future<void> _addStandard() async {
    final custom = TextEditingController();
    final conc = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Which standard?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, children: [
            for (final c in standardLevels)
              ActionChip(label: Text('${c.toStringAsFixed(0)} mg/L'), onPressed: () => Navigator.pop(ctx, c)),
          ]),
          TextField(
            controller: custom,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Other (mg/L NO3-N)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(custom.text.trim())),
              child: const Text('Use other')),
        ],
      ),
    );
    if (conc == null || conc < 0 || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Standard ${conc.toStringAsFixed(conc < 10 ? 1 : 0)} mg/L'),
        content: const Text('Dip a fresh strip in the standard for about 1 second, shake off '
            'the excess, then tap Start. Use the same technique as for field readings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Start')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TimerScreen(request: MeasureRequest.calibration(conc, widget.curve.id!))));
    _load();
  }

  Future<void> _deletePoint(CalPointRecord p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this calibration strip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await s.db.deletePoint(p.id!);
      _load();
    }
  }

  Future<void> _deleteCurve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete curve "${widget.curve.name}"?'),
        content: const Text('Its calibration strips are deleted too. Saved readings keep their values.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await s.db.deleteCurve(widget.curve.id!);
    if (s.activeCurveId == widget.curve.id) s.activeCurveId = null;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final m = _model;
    final byLevel = <double, List<CalPointRecord>>{};
    for (final p in _points) {
      byLevel.putIfAbsent(p.concentration, () => []).add(p);
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.curve.name), actions: [
        IconButton(onPressed: _deleteCurve, icon: const Icon(Icons.delete_outline)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _addStandard, icon: const Icon(Icons.add_a_photo), label: const Text('Add standard')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        if (m == null)
          const Text('Add standards at two or more concentrations to build the curve.')
        else ...[
          Text('Calibration path', style: t.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            for (final l in m.levels)
              Expanded(
                  child: Column(children: [
                LabSwatch(lab: l.meanLab, size: 40),
                Text(l.concentration.toStringAsFixed(0), style: t.bodySmall),
                Text('n=${l.n}', style: t.bodySmall),
              ])),
          ]),
          const SizedBox(height: 8),
          Text(m.pooledSigma == null
              ? 'Scatter: not yet measured (add a second strip at any standard).'
              : 'Strip-to-strip scatter along the curve: ${m.pooledSigma!.toStringAsFixed(2)} ΔE'),
          const SizedBox(height: 4),
          // Sensitivity per segment: how much color change per mg/L. Higher
          // means more precise readings in that range.
          for (var i = 0; i < m.levels.length - 1; i++)
            Text(
                '${m.levels[i].concentration.toStringAsFixed(0)}–${m.levels[i + 1].concentration.toStringAsFixed(0)} mg/L: '
                '${((m.arc[i + 1] - m.arc[i]) / (m.levels[i + 1].concentration - m.levels[i].concentration)).toStringAsFixed(2)} ΔE per mg/L',
                style: t.bodySmall),
        ],
        const Divider(height: 32),
        for (final e in byLevel.entries) ...[
          Text('${e.key.toStringAsFixed(e.key < 10 ? 1 : 0)} mg/L NO3-N', style: t.titleSmall),
          for (final p in e.value)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: LabSwatch(lab: p.lab, size: 36),
              title: Text(labText(p.lab)),
              subtitle: Text('${p.time.toLocal().toString().substring(0, 16)} · card fit ${p.cardRmsDeltaE.toStringAsFixed(1)} ΔE'),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _deletePoint(p)),
            ),
        ],
      ]),
    );
  }
}
