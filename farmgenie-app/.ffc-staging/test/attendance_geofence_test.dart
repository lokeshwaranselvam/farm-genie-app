import 'dart:math' as math;

import 'package:farmgenie/services/attendance_geofence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in AttendanceGeofence.offices.entries) {
    test('${entry.key}: center and 199/201 meter boundaries', () {
      final (lat, lon) = entry.value;
      expect(AttendanceGeofence.distanceMeters(entry.key, lat, lon), 0);
      for (final meters in [150.0, 199.0, 201.0]) {
        final offset = meters / 6371000 * 180 / math.pi;
        final distance = AttendanceGeofence.distanceMeters(
          entry.key,
          lat + offset,
          lon,
        )!;
        expect(distance, closeTo(meters, .00001));
        expect(distance <= AttendanceGeofence.radiusMeters, meters < 200);
      }
    });
  }

  test(
    'page spelling maps to existing office; unknown office fails closed',
    () {
      expect(
        AttendanceGeofence.distanceMeters(
          'Head Office - Aalapakkam',
          13.0431622,
          80.1609604,
        ),
        0,
      );
      expect(AttendanceGeofence.distanceMeters('Unknown', 13, 80), isNull);
      expect(AttendanceGeofence.distanceMeters('Operation', 13, 80), isNull);
    },
  );

  test('invalid and non-finite coordinates fail closed', () {
    for (final point in [
      (double.nan, 80.0),
      (13.0, double.infinity),
      (91.0, 80.0),
      (13.0, -181.0),
    ]) {
      expect(
        AttendanceGeofence.distanceMeters(
          'Head Office - Vanagaram',
          point.$1,
          point.$2,
        ),
        isNull,
      );
    }
  });

  test('inside requires the radius and a fix accurate to 50 meters', () {
    expect(AttendanceGeofence.maximumAccuracyMeters, 50);
    expect(AttendanceGeofence.isInside(150, 20), isTrue);
    expect(AttendanceGeofence.isInside(200, 50), isTrue);
    expect(AttendanceGeofence.isInside(201, 5), isFalse);
    // A coarse fix is rejected even when its centre is inside.
    expect(AttendanceGeofence.isInside(10, 51), isFalse);
    // Unknown accuracy (0 or negative) and non-finite values fail closed.
    expect(AttendanceGeofence.isInside(10, 0), isFalse);
    expect(AttendanceGeofence.isInside(10, -1), isFalse);
    expect(AttendanceGeofence.isInside(10, double.nan), isFalse);
    expect(AttendanceGeofence.isInside(double.nan, 10), isFalse);
    expect(
      AttendanceGeofence.inaccurateLocationMessage(87.4),
      allOf(contains('87 m'), contains('open sky')),
    );
  });

  test('mocked and stale fixes are rejected; fresh real fixes pass', () {
    final now = DateTime.utc(2026, 10, 27, 9);
    expect(
      AttendanceGeofence.fixProblem(
        isMocked: false,
        timestamp: now.subtract(const Duration(seconds: 5)),
        now: now,
      ),
      isNull,
    );
    expect(
      AttendanceGeofence.fixProblem(isMocked: true, timestamp: now, now: now),
      'Turn off fake/mock location apps to mark attendance.',
    );
    expect(
      AttendanceGeofence.fixProblem(
        isMocked: false,
        timestamp: now.subtract(const Duration(seconds: 31)),
        now: now,
      ),
      AttendanceGeofence.staleLocationMessage,
    );
    expect(
      AttendanceGeofence.isFreshFix(
        now.subtract(const Duration(seconds: 30)),
        now,
      ),
      isTrue,
    );
  });
}
