import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../core/config/app_config.dart';
import '../../../data/services/profile_services.dart';
import 'auth_provider.dart';

/// Sesión de la app con caducidad por inactividad.
///
/// Firebase Auth mantiene su propio token (1 hora, se renueva solo) y no
/// permite cambiar esa duración en el plan gratuito. Por eso la sesión de
/// SelvaCheck se controla aquí: si pasan [timeout] sin actividad, se cierra
/// la sesión de Firebase y hay que volver a ingresar con la contraseña.
///
/// - Cada toque en la pantalla renueva la sesión ([touch]).
/// - La última actividad se guarda en el teléfono, así que también caduca si
///   la app se cerró o quedó en segundo plano más de [timeout].
/// - Una pantalla puede mantenerla abierta sin toques con [hold] (la clase en
///   vivo, mientras el docente proyecta el QR).
class SessionController extends ChangeNotifier with WidgetsBindingObserver {
  SessionController(
    this._prefs,
    this._auth, {
    this.timeout = AppConfig.sessionTimeout,
    DateTime Function()? clock,
    Duration checkEvery = const Duration(seconds: 30),
  }) : _now = clock ?? DateTime.now {
    WidgetsBinding.instance.addObserver(this);
    _wasSignedIn = _signedIn;
    _auth.addListener(_onAuthChanged);
    if (_signedIn) _checkStoredActivity();
    _timer = Timer.periodic(checkEvery, (_) => check());
  }

  final PreferencesStore _prefs;
  final AuthProvider _auth;
  final Duration timeout;
  final DateTime Function() _now;
  Timer? _timer;

  DateTime? _lastActivity;
  DateTime? _lastSaved;
  int _holds = 0;
  bool _wasSignedIn = false;
  bool _expiring = false;
  bool _disposed = false;

  /// `true` si la última sesión se cerró por inactividad (para avisarlo en
  /// el inicio de sesión). Se borra al volver a ingresar.
  bool expiredByInactivity = false;

  bool get _signedIn =>
      _auth.status == AuthStatus.teacher || _auth.status == AuthStatus.student;

  /// Tiempo que queda antes de que caduque (para pruebas y depuración).
  Duration? get remaining {
    final last = _lastActivity;
    if (last == null || !_signedIn) return null;
    final left = timeout - _now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  /// Registra actividad. Se guarda en el teléfono como mucho cada 15 s.
  void touch() {
    if (!_signedIn) return;
    final now = _now();
    _lastActivity = now;
    final saved = _lastSaved;
    if (saved == null || now.difference(saved) >= const Duration(seconds: 15)) {
      _lastSaved = now;
      _prefs.setString(PrefKeys.lastActivity, now.toIso8601String());
    }
  }

  /// Mantiene la sesión abierta hasta llamar a la función devuelta.
  VoidCallback hold() {
    _holds++;
    touch();
    var released = false;
    return () {
      if (released) return;
      released = true;
      _holds--;
      touch();
    };
  }

  /// Cierra la sesión si ya pasó el tiempo sin actividad.
  Future<void> check() async {
    if (!_signedIn || _expiring) return;
    if (_holds > 0) {
      touch();
      return;
    }
    final last = _lastActivity;
    if (last != null && _now().difference(last) >= timeout) {
      await _expire();
    }
  }

  void _checkStoredActivity() {
    final stored = DateTime.tryParse(
      _prefs.getString(PrefKeys.lastActivity) ?? '',
    );
    if (stored == null) {
      touch();
      return;
    }
    _lastActivity = stored;
    unawaited(check());
  }

  void _onAuthChanged() {
    final signedIn = _signedIn;
    if (signedIn && !_wasSignedIn) {
      // Al iniciar la app con una sesión guardada, se respeta la última
      // actividad; al ingresar con contraseña, la sesión empieza de cero.
      _wasSignedIn = true;
      if (_lastActivity == null &&
          (_prefs.getString(PrefKeys.lastActivity) ?? '').isNotEmpty &&
          !expiredByInactivity) {
        _checkStoredActivity();
      } else {
        if (expiredByInactivity) {
          expiredByInactivity = false;
          _notify();
        }
        _lastSaved = null;
        touch();
      }
      return;
    } else if (!signedIn && _wasSignedIn) {
      // Al cerrar sesión se olvida la última actividad: el próximo ingreso
      // con contraseña empieza una sesión nueva.
      _lastActivity = null;
      _lastSaved = null;
      _prefs.setString(PrefKeys.lastActivity, '');
    }
    _wasSignedIn = signedIn;
  }

  Future<void> _expire() async {
    _expiring = true;
    expiredByInactivity = true;
    _lastActivity = null;
    _lastSaved = null;
    await _prefs.setString(PrefKeys.lastActivity, '');
    _notify();
    try {
      await _auth.signOut();
    } finally {
      _expiring = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(check());
    } else if (state == AppLifecycleState.paused) {
      // Guarda la última actividad real antes de pasar a segundo plano.
      final last = _lastActivity;
      if (last != null && _signedIn) {
        _prefs.setString(PrefKeys.lastActivity, last.toIso8601String());
      }
    }
  }

  /// Ya no se avisa en el inicio de sesión.
  void dismissNotice() {
    if (!expiredByInactivity) return;
    expiredByInactivity = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _auth.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Cuenta cada toque en la app como actividad de la sesión.
class SessionActivityDetector extends StatelessWidget {
  const SessionActivityDetector({
    super.key,
    required this.session,
    required this.child,
  });

  final SessionController session;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => session.touch(),
      child: child,
    );
  }
}
