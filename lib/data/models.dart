import '../color/vec3.dart';

/// Conversion between the two ways nitrate is reported.
/// Nitrate-nitrogen (NO3-N) counts only the mass of the nitrogen atom;
/// nitrate (NO3-) counts the whole ion. Ratio of molar masses:
///   62.004 g/mol (NO3-) / 14.007 g/mol (N) = 4.427.
const double no3PerNo3N = 4.427;

/// A calibration curve for one strip lot.
class CurveRecord {
  final int? id;
  final String name;
  final String lot;
  final DateTime created;
  final String notes;
  const CurveRecord({this.id, required this.name, this.lot = '', required this.created, this.notes = ''});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'lot': lot,
        'created': created.toIso8601String(),
        'notes': notes,
      };
  factory CurveRecord.fromMap(Map<String, Object?> m) => CurveRecord(
        id: m['id'] as int,
        name: m['name'] as String,
        lot: (m['lot'] as String?) ?? '',
        created: DateTime.parse(m['created'] as String),
        notes: (m['notes'] as String?) ?? '',
      );
}

/// One photographed strip from a known standard.
class CalPointRecord {
  final int? id;
  final int curveId;
  final double concentration; // mg/L NO3-N
  final Vec3 lab;
  final double cardRmsDeltaE;
  final DateTime time;
  final String? photoPath;
  const CalPointRecord({
    this.id,
    required this.curveId,
    required this.concentration,
    required this.lab,
    required this.cardRmsDeltaE,
    required this.time,
    this.photoPath,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'curve_id': curveId,
        'conc': concentration,
        'l': lab.x,
        'a': lab.y,
        'b': lab.z,
        'card_rms': cardRmsDeltaE,
        'time': time.toIso8601String(),
        'photo': photoPath,
      };
  factory CalPointRecord.fromMap(Map<String, Object?> m) => CalPointRecord(
        id: m['id'] as int,
        curveId: m['curve_id'] as int,
        concentration: (m['conc'] as num).toDouble(),
        lab: Vec3((m['l'] as num).toDouble(), (m['a'] as num).toDouble(), (m['b'] as num).toDouble()),
        cardRmsDeltaE: (m['card_rms'] as num).toDouble(),
        time: DateTime.parse(m['time'] as String),
        photoPath: m['photo'] as String?,
      );
}

/// One field reading.
class ReadingRecord {
  final int? id;
  final DateTime time;
  final String site;
  final double? latitude, longitude, gpsAccuracyM;
  final double no3n, low, high; // mg/L NO3-N
  final bool belowRange, aboveRange, provisional;
  final Vec3 lab;
  final double cardRmsDeltaE, offCurveDeltaE;
  final int? curveId;
  final String curveName;
  final int devTimeSeconds;
  final double captureDelaySeconds;
  final String? photoPath;
  final String notes;

  const ReadingRecord({
    this.id,
    required this.time,
    required this.site,
    this.latitude,
    this.longitude,
    this.gpsAccuracyM,
    required this.no3n,
    required this.low,
    required this.high,
    required this.belowRange,
    required this.aboveRange,
    required this.provisional,
    required this.lab,
    required this.cardRmsDeltaE,
    required this.offCurveDeltaE,
    required this.curveId,
    required this.curveName,
    required this.devTimeSeconds,
    required this.captureDelaySeconds,
    this.photoPath,
    this.notes = '',
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'time': time.toIso8601String(),
        'site': site,
        'lat': latitude,
        'lon': longitude,
        'gps_acc': gpsAccuracyM,
        'no3n': no3n,
        'low': low,
        'high': high,
        'below': belowRange ? 1 : 0,
        'above': aboveRange ? 1 : 0,
        'provisional': provisional ? 1 : 0,
        'l': lab.x,
        'a': lab.y,
        'b': lab.z,
        'card_rms': cardRmsDeltaE,
        'off_curve': offCurveDeltaE,
        'curve_id': curveId,
        'curve_name': curveName,
        'dev_time': devTimeSeconds,
        'capture_delay': captureDelaySeconds,
        'photo': photoPath,
        'notes': notes,
      };

  factory ReadingRecord.fromMap(Map<String, Object?> m) {
    double? od(String k) => (m[k] as num?)?.toDouble();
    double d(String k) => (m[k] as num).toDouble();
    return ReadingRecord(
      id: m['id'] as int,
      time: DateTime.parse(m['time'] as String),
      site: m['site'] as String,
      latitude: od('lat'),
      longitude: od('lon'),
      gpsAccuracyM: od('gps_acc'),
      no3n: d('no3n'),
      low: d('low'),
      high: d('high'),
      belowRange: m['below'] == 1,
      aboveRange: m['above'] == 1,
      provisional: m['provisional'] == 1,
      lab: Vec3(d('l'), d('a'), d('b')),
      cardRmsDeltaE: d('card_rms'),
      offCurveDeltaE: d('off_curve'),
      curveId: m['curve_id'] as int?,
      curveName: (m['curve_name'] as String?) ?? '',
      devTimeSeconds: (m['dev_time'] as num).toInt(),
      captureDelaySeconds: d('capture_delay'),
      photoPath: m['photo'] as String?,
      notes: (m['notes'] as String?) ?? '',
    );
  }
}

/// Formats a concentration with sensible precision and range flags.
String formatConc(double v, {bool below = false, bool above = false}) {
  if (above) return '> ${v.toStringAsFixed(0)}';
  if (below) return '< ${v.toStringAsFixed(v < 1 ? 1 : 0)}';
  return v < 10 ? v.toStringAsFixed(1) : v.toStringAsFixed(0);
}
