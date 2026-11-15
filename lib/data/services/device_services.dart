import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/attendance_checks.dart';

/// Lectura de ubicación del dispositivo.
class LocationReading {
  const LocationReading({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.isMocked,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final bool isMocked;
}

enum LocationProblem { serviceDisabled, denied, deniedForever, timeout }

class LocationException implements Exception {
  const LocationException(this.problem);

  final LocationProblem problem;

  String get message => switch (problem) {
    LocationProblem.serviceDisabled =>
      'La ubicación del teléfono está apagada. Actívala para continuar.',
    LocationProblem.denied =>
      'Necesitamos permiso de ubicación para verificar que estás en el aula.',
    LocationProblem.deniedForever =>
      'El permiso de ubicación está bloqueado. Actívalo en los ajustes de '
          'la app.',
    LocationProblem.timeout =>
      'No se pudo obtener la ubicación. Acércate a una ventana e inténtalo '
          'de nuevo.',
  };
}

/// Ubicación del dispositivo. Es abstracta para poder sustituirla en pruebas.
abstract class LocationService {
  /// Pide permisos si hace falta y devuelve la ubicación actual.
  /// Lanza [LocationException].
  Future<LocationReading> current();

  /// Abre los ajustes adecuados para resolver [problem].
  Future<void> openSettingsFor(LocationProblem problem);
}

class DeviceLocationService implements LocationService {
  @override
  Future<LocationReading> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationProblem.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(LocationProblem.deniedForever);
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(LocationProblem.denied);
    }
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationReading(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
      );
    } on Exception {
      throw const LocationException(LocationProblem.timeout);
    }
  }

  @override
  Future<void> openSettingsFor(LocationProblem problem) async {
    if (problem == LocationProblem.serviceDisabled) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

/// Información de WiFi del dispositivo. Requiere el permiso de ubicación.
abstract class WifiService {
  /// BSSID del router al que está conectado, o `null`.
  Future<String?> connectedBssid();

  /// BSSID de los routers cercanos, del más fuerte al más débil.
  Future<List<String>> nearbyBssids();
}

class DeviceWifiService implements WifiService {
  final _info = NetworkInfo();

  @override
  Future<String?> connectedBssid() async {
    try {
      return normalizeBssid(await _info.getWifiBSSID());
    } on Exception {
      return null;
    }
  }

  @override
  Future<List<String>> nearbyBssids() async {
    final scan = WiFiScan.instance;
    try {
      // Android limita los escaneos (4 cada 2 min); si no se puede escanear
      // se usan los últimos resultados disponibles.
      if (await scan.canStartScan(askPermissions: true) == CanStartScan.yes) {
        await scan.startScan();
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      if (await scan.canGetScannedResults(askPermissions: true) !=
          CanGetScannedResults.yes) {
        return const [];
      }
      final results = await scan.getScannedResults();
      final sorted = [...results]..sort((a, b) => b.level.compareTo(a.level));
      return sorted
          .map((ap) => normalizeBssid(ap.bssid))
          .whereType<String>()
          .toSet()
          .take(AppConfig.maxSessionBssids)
          .toList();
    } on Exception {
      return const [];
    }
  }
}
