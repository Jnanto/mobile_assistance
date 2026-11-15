import 'dart:math';

import '../config/app_config.dart';

/// Contenido del QR dinámico: `SC1|{sesionId}|{token}`.
class QrPayload {
  const QrPayload(this.sessionId, this.token);

  static const _prefix = 'SC1';

  final String sessionId;
  final String token;

  String encode() => '$_prefix|$sessionId|$token';

  /// Devuelve `null` si el texto no es un QR de SelvaCheck.
  static QrPayload? parse(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().split('|');
    if (parts.length != 3 || parts[0] != _prefix) return null;
    if (parts[1].isEmpty || parts[2].isEmpty) return null;
    return QrPayload(parts[1], parts[2]);
  }

  static const _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  /// Token aleatorio criptográficamente seguro.
  static String newToken([Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      20,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
  }
}

/// Distancia en metros entre dos coordenadas (fórmula de haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371000.0;
  double rad(double deg) => deg * pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
  return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
}

enum GpsIssue { outOfRange, mocked, unavailable }

class GpsCheck {
  const GpsCheck({required this.ok, this.distance, this.accuracy, this.issue});

  final bool ok;
  final double? distance;
  final double? accuracy;
  final GpsIssue? issue;
}

/// Compara la ubicación del estudiante con la tomada por el docente.
///
/// Se acepta si la distancia no supera el radio más la precisión reportada
/// (con un tope), porque el GPS en interiores tiene errores de decenas de
/// metros. Una ubicación simulada nunca se acepta.
GpsCheck evaluateGps({
  required double classLat,
  required double classLng,
  required int radiusMeters,
  required double lat,
  required double lng,
  required double accuracy,
  required bool isMocked,
}) {
  final distance = distanceMeters(classLat, classLng, lat, lng);
  if (isMocked) {
    return GpsCheck(
      ok: false,
      distance: distance,
      accuracy: accuracy,
      issue: GpsIssue.mocked,
    );
  }
  final allowance = min(accuracy, AppConfig.gpsAccuracyAllowanceMeters);
  final ok = distance <= radiusMeters + allowance;
  return GpsCheck(
    ok: ok,
    distance: distance,
    accuracy: accuracy,
    issue: ok ? null : GpsIssue.outOfRange,
  );
}

enum WifiIssue { notConnected, notInClassroom }

class WifiCheck {
  const WifiCheck({required this.ok, this.bssid, this.issue});

  final bool ok;
  final String? bssid;
  final WifiIssue? issue;
}

/// Normaliza un BSSID; devuelve `null` si no es válido o es el valor que
/// Android entrega cuando no hay permiso (`02:00:00:00:00:00`).
String? normalizeBssid(String? bssid) {
  if (bssid == null) return null;
  final value = bssid.trim().toLowerCase();
  final valid = RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$').hasMatch(value);
  if (!valid) return null;
  if (value == '02:00:00:00:00:00' || value == '00:00:00:00:00:00') {
    return null;
  }
  return value;
}

/// El estudiante pasa si el router al que está conectado es uno de los que
/// registró el teléfono del docente al iniciar la clase.
WifiCheck evaluateWifi({
  required List<String> classBssids,
  required String? studentBssid,
}) {
  final bssid = normalizeBssid(studentBssid);
  if (bssid == null) {
    return const WifiCheck(ok: false, issue: WifiIssue.notConnected);
  }
  final ok = classBssids.map(normalizeBssid).contains(bssid);
  return WifiCheck(
    ok: ok,
    bssid: bssid,
    issue: ok ? null : WifiIssue.notInClassroom,
  );
}
