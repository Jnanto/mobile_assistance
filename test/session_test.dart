import 'package:asis_selva_check/data/services/profile_services.dart';
import 'package:asis_selva_check/features/auth/providers/auth_provider.dart';
import 'package:asis_selva_check/features/auth/providers/session_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// AuthProvider mínimo: solo estado y cierre de sesión.
class _Auth extends ChangeNotifier implements AuthProvider {
  _Auth(this._status);

  AuthStatus _status;
  int signOuts = 0;

  @override
  AuthStatus get status => _status;

  set signedInAs(AuthStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    signedInAs = AuthStatus.signedOut;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late InMemoryPreferences prefs;

  SessionController build(_Auth auth) => SessionController(
    prefs,
    auth,
    clock: () => now,
    checkEvery: const Duration(hours: 1),
  );

  setUp(() {
    now = DateTime(2026, 11, 2, 14);
    prefs = InMemoryPreferences();
  });

  test('cierra la sesión tras 10 minutos sin actividad', () async {
    final auth = _Auth(AuthStatus.teacher);
    final session = build(auth);
    addTearDown(session.dispose);

    now = now.add(const Duration(minutes: 9));
    await session.check();
    expect(auth.signOuts, 0);

    now = now.add(const Duration(minutes: 1));
    await session.check();
    expect(auth.signOuts, 1);
    expect(session.expiredByInactivity, isTrue);
  });

  test('cada toque renueva la sesión', () async {
    final auth = _Auth(AuthStatus.student);
    final session = build(auth);
    addTearDown(session.dispose);

    for (var i = 0; i < 5; i++) {
      now = now.add(const Duration(minutes: 8));
      session.touch();
      await session.check();
    }
    expect(auth.signOuts, 0);
    expect(session.remaining, const Duration(minutes: 10));
  });

  test('la clase en vivo la mantiene abierta sin toques', () async {
    final auth = _Auth(AuthStatus.teacher);
    final session = build(auth);
    addTearDown(session.dispose);

    final release = session.hold();
    now = now.add(const Duration(minutes: 45));
    await session.check();
    expect(auth.signOuts, 0);

    release();
    now = now.add(const Duration(minutes: 10));
    await session.check();
    expect(auth.signOuts, 1);
  });

  test('caduca al abrir la app si la última actividad es vieja', () async {
    await prefs.setString(
      PrefKeys.lastActivity,
      now.subtract(const Duration(minutes: 30)).toIso8601String(),
    );
    // La app arranca cargando y luego restaura la sesión guardada.
    final auth = _Auth(AuthStatus.loading);
    final session = build(auth);
    addTearDown(session.dispose);
    auth.signedInAs = AuthStatus.teacher;
    await Future<void>.delayed(Duration.zero);
    expect(auth.signOuts, 1);
    expect(session.expiredByInactivity, isTrue);

    // Al volver a ingresar con contraseña empieza una sesión nueva.
    auth.signedInAs = AuthStatus.teacher;
    expect(session.expiredByInactivity, isFalse);
    now = now.add(const Duration(minutes: 5));
    await session.check();
    expect(auth.signOuts, 1);
  });

  test('cerrar sesión a mano no deja una actividad vieja guardada', () async {
    final auth = _Auth(AuthStatus.teacher);
    final session = build(auth);
    addTearDown(session.dispose);

    await auth.signOut();
    now = now.add(const Duration(hours: 3));
    auth.signedInAs = AuthStatus.teacher;
    await session.check();
    expect(auth.signOuts, 1);
    expect(session.expiredByInactivity, isFalse);
  });
}
