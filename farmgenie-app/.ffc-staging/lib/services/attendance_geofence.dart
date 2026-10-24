import 'dart:math' as math;

/// Office policy from the supplied attendance page. ERP enforces it as well.
class AttendanceGeofence {
  AttendanceGeofence._();

  static const radiusMeters = 200.0;
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
