import 'package:flutter/widgets.dart';

import '../../core/config/app_config.dart';
import '../../data/models/course.dart';
import '../../data/services/profile_services.dart';

/// Avisos locales antes de cada clase. La preferencia es de este teléfono.
class RemindersController extends ChangeNotifier {
  RemindersController(this._prefs, this._service);

  final PreferencesStore _prefs;
  final ReminderService _service;
  List<Course> _courses = const [];
  String? _lastSignature;

  bool get enabled => _prefs.getBool(PrefKeys.remindersEnabled);

  /// Cuántos avisos semanales hay con los cursos actuales.
  int get count => remindersFor(_courses).length;

  /// Devuelve un mensaje si no se pudo activar.
  Future<String?> setEnabled(bool value) async {
    if (value && !await _service.requestPermission()) {
      return 'Permite las notificaciones de SelvaCheck en los ajustes del '
          'teléfono.';
    }
    await _prefs.setBool(PrefKeys.remindersEnabled, value);
    _lastSignature = null;
    if (value) {
      await _apply();
    } else {
      await _service.cancelAll();
    }
    notifyListeners();
    return null;
  }

  /// Se llama cuando cambian los cursos del usuario.
  Future<void> sync(List<Course> courses) async {
    _courses = courses;
    notifyListeners();
    if (enabled) await _apply();
  }

  /// Al cerrar sesión: que otra cuenta en este teléfono no reciba los avisos.
  Future<void> clear() async {
    _courses = const [];
    _lastSignature = null;
    try {
      await _service.cancelAll();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _apply() async {
    final reminders = remindersFor(_courses);
    final signature = reminders
        .map((r) => '${r.weekday}:${r.minuteOfDay}:${r.title}:${r.body}')
        .join('|');
    if (signature == _lastSignature) return;
    _lastSignature = signature;
    try {
      await _service.schedule(reminders);
    } catch (_) {
      _lastSignature = null;
    }
  }
}

/// Bloqueo de la app con la huella (o el PIN del teléfono).
class AppLockController extends ChangeNotifier with WidgetsBindingObserver {
  AppLockController(this._prefs, this._biometric) {
    WidgetsBinding.instance.addObserver(this);
    _locked = enabled;
  }

  final PreferencesStore _prefs;
  final BiometricService _biometric;
  bool _locked = false;
  bool _authenticating = false;
  DateTime? _backgroundSince;

  bool get enabled => _prefs.getBool(PrefKeys.biometricLock);

  bool get locked => enabled && _locked;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundSince ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundSince;
      _backgroundSince = null;
      if (enabled &&
          !_authenticating &&
          since != null &&
          DateTime.now().difference(since) >= AppConfig.relockAfter) {
        _locked = true;
        notifyListeners();
      }
    }
  }

  Future<bool> unlock() async {
    if (_authenticating) return false;
    _authenticating = true;
    final ok = await _biometric.authenticate('Desbloquea SelvaCheck');
    _authenticating = false;
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  /// Devuelve un mensaje si no se pudo activar.
  Future<String?> setEnabled(bool value) async {
    if (value) {
      if (!await _biometric.isAvailable()) {
        return 'Tu teléfono no tiene huella ni bloqueo de pantalla '
            'configurado.';
      }
      _authenticating = true;
      final ok = await _biometric.authenticate(
        'Confirma tu identidad para activar el bloqueo',
      );
      _authenticating = false;
      if (!ok) return 'No se pudo confirmar tu identidad.';
    }
    await _prefs.setBool(PrefKeys.biometricLock, value);
    _locked = false;
    notifyListeners();
    return null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
