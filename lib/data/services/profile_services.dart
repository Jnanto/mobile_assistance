import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/config/app_config.dart';
import '../../core/utils/schedule_format.dart';
import '../models/course.dart';

// ---------------------------------------------------------------------------
// Preferencias locales (por teléfono)
// ---------------------------------------------------------------------------

/// Preferencias guardadas en el teléfono. Abstracta para las pruebas.
abstract class PreferencesStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  bool getBool(String key, {bool fallback = false});
  Future<void> setBool(String key, bool value);
}

class SharedPreferencesStore implements PreferencesStore {
  SharedPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<SharedPreferencesStore> load() async =>
      SharedPreferencesStore(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  @override
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
}

abstract final class PrefKeys {
  static const deviceId = 'selvacheck.deviceId';
  static const remindersEnabled = 'selvacheck.reminders';
  static const biometricLock = 'selvacheck.biometricLock';
  static const lastActivity = 'selvacheck.lastActivity';
}

// ---------------------------------------------------------------------------
// Identidad del dispositivo
// ---------------------------------------------------------------------------

class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.model});

  /// Identificador de esta instalación de la app.
  final String id;

  /// "Samsung SM-A546E"
  final String model;
}

/// Identifica el teléfono para vincular la cuenta del estudiante.
///
/// Se usa un identificador aleatorio guardado al instalar la app: Android ya no
/// entrega un identificador fijo del hardware. Si se reinstala la app o se
/// borran sus datos, el identificador cambia y el docente debe desvincular la
/// cuenta para volver a vincularla.
abstract class DeviceIdentityService {
  Future<DeviceIdentity> current();
}

class DeviceIdentityServiceImpl implements DeviceIdentityService {
  DeviceIdentityServiceImpl(this._prefs);

  final PreferencesStore _prefs;
  DeviceIdentity? _cached;

  static const _alphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';

  @override
  Future<DeviceIdentity> current() async {
    final cached = _cached;
    if (cached != null) return cached;
    var id = _prefs.getString(PrefKeys.deviceId);
    if (id == null || id.length < 16) {
      final rng = Random.secure();
      id = List.generate(
        24,
        (_) => _alphabet[rng.nextInt(_alphabet.length)],
      ).join();
      await _prefs.setString(PrefKeys.deviceId, id);
    }
    var model = 'Teléfono Android';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final brand = info.manufacturer.isEmpty
          ? ''
          : '${info.manufacturer[0].toUpperCase()}'
                '${info.manufacturer.substring(1)} ';
      model = '$brand${info.model}'.trim();
    } catch (_) {
      // Sin información del modelo: se usa el texto genérico.
    }
    return _cached = DeviceIdentity(id: id, model: model);
  }
}

// ---------------------------------------------------------------------------
// Recordatorios locales antes de clase
// ---------------------------------------------------------------------------

/// Un aviso semanal: día (1 = lunes) y minuto del día en que suena.
class WeeklyReminder {
  const WeeklyReminder({
    required this.id,
    required this.weekday,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final int weekday;
  final int minuteOfDay;
  final String title;
  final String body;
}

/// Avisos [AppConfig.reminderMinutesBefore] minutos antes de cada clase de
/// los cursos publicados.
List<WeeklyReminder> remindersFor(List<Course> courses) {
  final before = AppConfig.reminderMinutesBefore;
  final reminders = <WeeklyReminder>[];
  final active = courses.where((c) => c.status == CourseStatus.active).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  for (final course in active) {
    for (final meeting in course.meetings) {
      var minute = meeting.startMinutes - before;
      var weekday = meeting.day;
      if (minute < 0) {
        minute += 24 * 60;
        weekday = meeting.day == 1 ? 7 : meeting.day - 1;
      }
      reminders.add(
        WeeklyReminder(
          id: reminders.length + 1,
          weekday: weekday,
          minuteOfDay: minute,
          title: '${course.name} en $before min',
          body: [
            ScheduleFormat.time(meeting.startMinutes),
            meeting.locationLabel,
          ].where((s) => s.isNotEmpty).join(' · '),
        ),
      );
    }
  }
  return reminders;
}

abstract class ReminderService {
  /// Pide el permiso de notificaciones (Android 13+). `true` si se concedió.
  Future<bool> requestPermission();

  /// Reemplaza todos los avisos programados.
  Future<void> schedule(List<WeeklyReminder> reminders);

  Future<void> cancelAll();
}

class LocalReminderService implements ReminderService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channel = AndroidNotificationDetails(
    'recordatorios_clase',
    'Recordatorios de clase',
    channelDescription: 'Avisos antes de que empiece cada clase',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> _init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // La app se usa en Colombia (UTC-5, sin horario de verano).
      tz.setLocalLocation(tz.getLocation('America/Bogota'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    await _init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  @override
  Future<void> schedule(List<WeeklyReminder> reminders) async {
    await _init();
    await _plugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    for (final r in reminders) {
      var date = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        r.minuteOfDay ~/ 60,
        r.minuteOfDay % 60,
      );
      while (date.weekday != r.weekday || !date.isAfter(now)) {
        date = date.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: date,
        notificationDetails: const NotificationDetails(android: _channel),
        // Sin alarmas exactas: no requiere permisos especiales y basta para
        // un aviso con 15 minutos de anticipación.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }
}

// ---------------------------------------------------------------------------
// Huella / bloqueo del teléfono
// ---------------------------------------------------------------------------

abstract class BiometricService {
  /// El teléfono tiene huella, rostro o al menos un bloqueo de pantalla.
  Future<bool> isAvailable();

  /// Pide la huella (o el PIN del teléfono). `true` si se desbloqueó.
  Future<bool> authenticate(String reason);
}

class LocalBiometricService implements BiometricService {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
