import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

String _csvField(Object? v) {
  final s = v?.toString() ?? '';
  if (s.contains(RegExp(r'[",\n]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

/// The reading log as CSV text (one row per reading).
String readingsToCsv(List<ReadingRecord> rs) {
  final header = [
    'id', 'date_local', 'time_local', 'timestamp_iso', 'site', 'latitude', 'longitude', 'gps_accuracy_m',
    'nitrate_N_mg_L', 'nitrate_N_low_95', 'nitrate_N_high_95', 'nitrate_NO3_mg_L',
    'below_range', 'above_range', 'provisional_uncertainty',
    'L', 'a', 'b', 'card_fit_dE', 'off_curve_dE',
    'curve', 'dev_time_s', 'capture_delay_s', 'photo_file', 'notes',
  ];
  final lines = <String>[header.join(',')];
  for (final r in rs) {
    final t = r.time;
    String two(int v) => v.toString().padLeft(2, '0');
    lines.add([
      r.id,
      '${t.year}-${two(t.month)}-${two(t.day)}',
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}',
      t.toIso8601String(),
      r.site,
      r.latitude?.toStringAsFixed(6),
      r.longitude?.toStringAsFixed(6),
      r.gpsAccuracyM?.toStringAsFixed(0),
      r.no3n.toStringAsFixed(2),
      r.low.toStringAsFixed(2),
      r.high.toStringAsFixed(2),
      (r.no3n * no3PerNo3N).toStringAsFixed(1),
      r.belowRange,
      r.aboveRange,
      r.provisional,
      r.lab.x.toStringAsFixed(2),
      r.lab.y.toStringAsFixed(2),
      r.lab.z.toStringAsFixed(2),
      r.cardRmsDeltaE.toStringAsFixed(2),
      r.offCurveDeltaE.toStringAsFixed(2),
      r.curveName,
      r.devTimeSeconds,
      r.captureDelaySeconds.toStringAsFixed(0),
      r.photoPath == null ? '' : p.basename(r.photoPath!),
      r.notes,
    ].map(_csvField).join(','));
  }
  return '${lines.join('\r\n')}\r\n';
}

/// Writes the CSV (and optionally a ZIP with the photos) to a temp folder and
/// returns the file path, ready for the share sheet.
Future<String> exportReadings(List<ReadingRecord> rs, {bool withPhotos = false}) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
  final csv = readingsToCsv(rs);
  final csvPath = p.join(dir.path, 'nitrate_log_$stamp.csv');
  await File(csvPath).writeAsString(csv);
  if (!withPhotos) return csvPath;

  final zipPath = p.join(dir.path, 'nitrate_log_$stamp.zip');
  final enc = ZipFileEncoder()..create(zipPath);
  await enc.addFile(File(csvPath), 'nitrate_log.csv');
  for (final r in rs) {
    final photo = r.photoPath;
    if (photo != null && File(photo).existsSync()) {
      await enc.addFile(File(photo), 'photos/${p.basename(photo)}');
    }
  }
  await enc.close();
  return zipPath;
}
