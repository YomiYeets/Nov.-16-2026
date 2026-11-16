import 'package:flutter_test/flutter_test.dart';
import 'package:nitrate_reader/color/vec3.dart';
import 'package:nitrate_reader/data/export.dart';
import 'package:nitrate_reader/data/models.dart';

void main() {
  test('CSV has a header, quotes commas, and converts to NO3-', () {
    final r = ReadingRecord(
      id: 1,
      time: DateTime(2026, 11, 16, 9, 5, 7),
      site: 'Muddy Branch, upstream',
      latitude: 39.1234567,
      longitude: -77.2345678,
      gpsAccuracyM: 5,
      no3n: 4.2,
      low: 3.1,
      high: 5.6,
      belowRange: false,
      aboveRange: false,
      provisional: true,
      lab: const Vec3(80, 20, -3),
      cardRmsDeltaE: 1.1,
      offCurveDeltaE: 0.8,
      curveId: 1,
      curveName: 'Lot A',
      devTimeSeconds: 60,
      captureDelaySeconds: 4,
      photoPath: '/data/photos/strip_1.jpg',
      notes: 'clear water',
    );
    final lines = readingsToCsv([r]).trim().split('\r\n');
    expect(lines, hasLength(2));
    expect(lines[0], startsWith('id,date_local,time_local'));
    expect(lines[1], contains('"Muddy Branch, upstream"'));
    expect(lines[1], contains('2026-11-16,09:05:07'));
    expect(lines[1], contains(',18.6,')); // 4.2 * 4.427
    expect(lines[1], contains('strip_1.jpg'));
  });
}
