import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../app_services.dart';
import '../data/export.dart';
import '../data/models.dart';
import 'widgets.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});
  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final s = AppServices.instance;
  List<ReadingRecord> _rs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await s.db.readings();
    if (mounted) setState(() => _rs = r);
  }

  Future<void> _export({required bool photos}) async {
    if (_rs.isEmpty) return;
    final path = await exportReadings(_rs, withPhotos: photos);
    await SharePlus.instance.share(ShareParams(files: [XFile(path)], subject: 'Nitrate readings'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading log'), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.ios_share),
          onSelected: (v) => _export(photos: v == 'zip'),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            PopupMenuItem(value: 'zip', child: Text('Export CSV + photos (ZIP)')),
          ],
        ),
      ]),
      body: _rs.isEmpty
          ? const Center(child: Text('No readings yet.'))
          : ListView.separated(
              itemCount: _rs.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final r = _rs[i];
                return ListTile(
                  leading: LabSwatch(lab: r.lab, size: 40),
                  title: Text('${r.site} · ${formatConc(r.no3n, below: r.belowRange, above: r.aboveRange)} mg/L NO3-N'),
                  subtitle: Text('${r.time.toLocal().toString().substring(0, 16)} · '
                      '95%: ${r.low.toStringAsFixed(1)}–${r.high.toStringAsFixed(1)}'),
                  onTap: () async {
                    await Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ReadingDetailScreen(reading: r)));
                    _load();
                  },
                );
              },
            ),
    );
  }
}

class ReadingDetailScreen extends StatelessWidget {
  final ReadingRecord reading;
  const ReadingDetailScreen({super.key, required this.reading});

  @override
  Widget build(BuildContext context) {
    final r = reading;
    final photo = r.photoPath;
    Widget row(String k, String v) => ListTile(dense: true, title: Text(k), subtitle: Text(v));
    return Scaffold(
      appBar: AppBar(title: Text(r.site), actions: [
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete this reading?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                ],
              ),
            );
            if (ok != true) return;
            await AppServices.instance.db.deleteReading(r.id!);
            if (photo != null) {
              final f = File(photo);
              if (f.existsSync()) f.deleteSync();
            }
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ]),
      body: ListView(children: [
        if (photo != null && File(photo).existsSync()) Image.file(File(photo)),
        row('Nitrate-N', '${formatConc(r.no3n, below: r.belowRange, above: r.aboveRange)} mg/L '
            '(95%: ${r.low.toStringAsFixed(1)}–${r.high.toStringAsFixed(1)})'
            '${r.provisional ? ' · provisional range' : ''}'),
        row('Nitrate (NO3-)', '${(r.no3n * no3PerNo3N).toStringAsFixed(1)} mg/L'),
        row('Date & time', r.time.toLocal().toString().substring(0, 19)),
        row('Location', r.latitude == null
            ? 'Not recorded'
            : '${r.latitude!.toStringAsFixed(6)}, ${r.longitude!.toStringAsFixed(6)} (±${r.gpsAccuracyM?.toStringAsFixed(0)} m)'),
        row('Pad color', labText(r.lab)),
        row('Card fit / off-curve', '${r.cardRmsDeltaE.toStringAsFixed(2)} ΔE / ${r.offCurveDeltaE.toStringAsFixed(2)} ΔE'),
        row('Curve', r.curveName),
        row('Timing', '${r.devTimeSeconds} s development, photo +${r.captureDelaySeconds.toStringAsFixed(0)} s'),
        if (r.notes.isNotEmpty) row('Notes', r.notes),
      ]),
    );
  }
}
