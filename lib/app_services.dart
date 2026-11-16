import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analysis/card_layout.dart';
import 'data/database.dart';

/// App-wide singletons: database, settings and the card layout.
class AppServices {
  static late AppServices instance;

  final AppDatabase db;
  final SharedPreferences prefs;
  final CardLayout layout;
  final Directory photosDir;

  AppServices._(this.db, this.prefs, this.layout, this.photosDir);

  static Future<void> init() async {
    final db = await AppDatabase.open();
    final prefs = await SharedPreferences.getInstance();
    final layout = CardLayout.fromJson(await rootBundle.loadString('assets/card_layout.json'));
    final docs = await getApplicationDocumentsDirectory();
    final photos = Directory(p.join(docs.path, 'photos'))..createSync(recursive: true);
    instance = AppServices._(db, prefs, layout, photos);
  }

  /// Strip development time. Hach-style nitrate strips are typically read
  /// about 60 s after dipping. Check your strip's instructions. Use the SAME
  /// time for calibration and readings: the pad keeps darkening for a while.
  int get devTimeSeconds => prefs.getInt('devTimeSeconds') ?? 60;
  set devTimeSeconds(int v) => prefs.setInt('devTimeSeconds', v.clamp(5, 900));

  int? get activeCurveId => prefs.getInt('activeCurveId');
  set activeCurveId(int? v) =>
      v == null ? prefs.remove('activeCurveId') : prefs.setInt('activeCurveId', v);
}

/// What the camera/analyze flow is being used for.
enum MeasureMode { reading, calibration }

class MeasureRequest {
  final MeasureMode mode;

  /// For calibration: the standard's concentration (mg/L NO3-N) and curve.
  final double? standardConcentration;
  final int? curveId;

  const MeasureRequest.reading()
      : mode = MeasureMode.reading,
        standardConcentration = null,
        curveId = null;
  const MeasureRequest.calibration(double this.standardConcentration, int this.curveId)
      : mode = MeasureMode.calibration;
}
