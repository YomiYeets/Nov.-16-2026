import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../color/calibration_curve.dart';
import 'models.dart';

/// Local SQLite storage for curves, calibration points and readings.
class AppDatabase {
  final Database db;
  AppDatabase._(this.db);

  static Future<AppDatabase> open() async {
    final path = p.join(await getDatabasesPath(), 'nitrate_reader.db');
    final db = await openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''CREATE TABLE curves(
        id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, lot TEXT,
        created TEXT NOT NULL, notes TEXT)''');
      await db.execute('''CREATE TABLE cal_points(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        curve_id INTEGER NOT NULL REFERENCES curves(id) ON DELETE CASCADE,
        conc REAL NOT NULL, l REAL NOT NULL, a REAL NOT NULL, b REAL NOT NULL,
        card_rms REAL NOT NULL, time TEXT NOT NULL, photo TEXT)''');
      await db.execute('''CREATE TABLE readings(
        id INTEGER PRIMARY KEY AUTOINCREMENT, time TEXT NOT NULL, site TEXT NOT NULL,
        lat REAL, lon REAL, gps_acc REAL,
        no3n REAL NOT NULL, low REAL NOT NULL, high REAL NOT NULL,
        below INTEGER NOT NULL, above INTEGER NOT NULL, provisional INTEGER NOT NULL,
        l REAL NOT NULL, a REAL NOT NULL, b REAL NOT NULL,
        card_rms REAL NOT NULL, off_curve REAL NOT NULL,
        curve_id INTEGER, curve_name TEXT, dev_time INTEGER NOT NULL,
        capture_delay REAL NOT NULL, photo TEXT, notes TEXT)''');
    }, onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'));
    return AppDatabase._(db);
  }

  // ---- curves ----
  Future<List<CurveRecord>> curves() async =>
      (await db.query('curves', orderBy: 'created DESC')).map(CurveRecord.fromMap).toList();

  Future<CurveRecord?> curve(int id) async {
    final r = await db.query('curves', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : CurveRecord.fromMap(r.first);
  }

  Future<int> insertCurve(CurveRecord c) => db.insert('curves', c.toMap()..remove('id'));
  Future<void> deleteCurve(int id) => db.delete('curves', where: 'id = ?', whereArgs: [id]);

  // ---- calibration points ----
  Future<List<CalPointRecord>> points(int curveId) async => (await db.query('cal_points',
          where: 'curve_id = ?', whereArgs: [curveId], orderBy: 'conc, time'))
      .map(CalPointRecord.fromMap)
      .toList();

  Future<int> insertPoint(CalPointRecord pt) => db.insert('cal_points', pt.toMap()..remove('id'));
  Future<void> deletePoint(int id) => db.delete('cal_points', where: 'id = ?', whereArgs: [id]);

  /// Builds the model for a curve, or null if it has fewer than two levels.
  Future<CalibrationModel?> model(int curveId) async {
    final pts = await points(curveId);
    if (pts.map((p) => p.concentration).toSet().length < 2) return null;
    return CalibrationModel.fromSamples(
        [for (final p in pts) CalibrationSample(p.concentration, p.lab)]);
  }

  // ---- readings ----
  Future<List<ReadingRecord>> readings() async =>
      (await db.query('readings', orderBy: 'time DESC')).map(ReadingRecord.fromMap).toList();
  Future<int> insertReading(ReadingRecord r) => db.insert('readings', r.toMap()..remove('id'));
  Future<void> deleteReading(int id) => db.delete('readings', where: 'id = ?', whereArgs: [id]);

  Future<List<String>> siteNames() async {
    final r = await db.rawQuery('SELECT site, MAX(time) t FROM readings GROUP BY site ORDER BY t DESC');
    return r.map((e) => e['site'] as String).toList();
  }
}
