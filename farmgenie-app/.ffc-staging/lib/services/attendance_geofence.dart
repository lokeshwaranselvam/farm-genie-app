import 'dart:math' as math;

/// Office policy from the supplied attendance page. ERP enforces it as well.
class AttendanceGeofence {
  AttendanceGeofence._();

  /// No client fallback: the attendance API owns the office radius.
  static double? parseRadiusMeters(dynamic value) {
    final radius = double.tryParse('$value');
    return radius != null && radius.isFinite && radius > 0 ? radius : null;
  }

  /// Fixes reporting a worse horizontal accuracy than this are not trusted
  /// for a geofence decision; the user must wait for a better GPS signal.
  static const maximumAccuracyMeters = 50.0;

  /// Older fixes may be cached by the OS; a fresh one must be requested.
  static const maximumFixAge = Duration(seconds: 30);

  static const mockedLocationMessage =
      'Turn off fake/mock location apps to mark attendance.';
  static const staleLocationMessage =
      'Could not get a fresh GPS fix. Refresh location and try again.';

  static String inaccurateLocationMessage(double accuracy) =>
      'Your GPS signal is too weak'
      '${accuracy.isFinite && accuracy > 0 ? ' (about ${accuracy.round()} m)' : ''}. '
      'Move to open sky or wait a moment for better GPS, then try again.';
  static const offices = <String, (double, double)>{
    'Head Office - Alapakkam': (13.0431622, 80.1609604),
    'Head Office - RWD GrandCorridor': (13.0570, 80.1371),
    'Head Office - Vanagaram': (13.0549854, 80.1545772),
    'Head Office - Prestige': (13.0604, 80.15483),
  };

  static String canonicalOffice(String office) =>
      office == 'Head Office - Aalapakkam' ? 'Head Office - Alapakkam' : office;

  static bool validCoordinates(double latitude, double longitude) =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// A fix older than [maximumFixAge] is stale. A timestamp ahead of the
  /// device clock is not treated as stale (GPS time and a manually set phone
  /// clock can disagree); the server checks capture time as well.
  static bool isFreshFix(DateTime timestamp, DateTime now) =>
      now.difference(timestamp) <= maximumFixAge;

  /// Platforms report 0 or a negative value when accuracy is unknown.
  static bool isAccurateFix(double accuracy) =>
      accuracy.isFinite && accuracy > 0 && accuracy <= maximumAccuracyMeters;

  /// Integrity problems that apply to every attendance fix, geofenced or not.
  /// Returns null when the fix may be used.
  static String? fixProblem({
    required bool isMocked,
    required DateTime timestamp,
    required DateTime now,
  }) {
    if (isMocked) return mockedLocationMessage;
    if (!isFreshFix(timestamp, now)) return staleLocationMessage;
    return null;
  }

  /// Geofence decision: inside only when the fix centre is within
  /// [radiusMeters] AND the fix is accurate to [maximumAccuracyMeters].
  /// Accuracy is deliberately not added to or subtracted from the distance;
  /// a coarse fix is rejected rather than given the benefit of the doubt.
  static bool isInside(
    double distance,
    double accuracy, {
    required double radiusMeters,
  }) =>
      radiusMeters.isFinite &&
      radiusMeters > 0 &&
      distance.isFinite &&
      distance >= 0 &&
      distance <= radiusMeters &&
      isAccurateFix(accuracy);

  static double? distanceMeters(
    String office,
    double latitude,
    double longitude,
  ) {
    final center = offices[canonicalOffice(office)];
    if (center == null || !validCoordinates(latitude, longitude)) return null;
    const radians = math.pi / 180;
    final dLat = (latitude - center.$1) * radians;
    final dLon = (longitude - center.$2) * radians;
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(center.$1 * radians) *
            math.cos(latitude * radians) *
            math.pow(math.sin(dLon / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}
