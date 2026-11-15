import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../data/models/app_user.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/profile_services.dart';

/// En qué punto del flujo de autenticación está el usuario. El router decide
/// la pantalla a partir de este valor.
enum AuthStatus {
  loading,
  signedOut,
  emailNotVerified,
  needsLink,
  teacher,
  student,
}

/// Relación entre la cuenta y este teléfono.
enum DeviceBinding {
  /// Aún no se sabe (cargando) o no aplica (docentes).
  unknown,

  /// La cuenta está vinculada a este teléfono.
  thisDevice,

  /// La cuenta está vinculada a otro teléfono: no puede marcar asistencia.
  otherDevice,
}

/// Por qué un estudiante aún no puede usar la app tras verificar su correo.
enum LinkProblem { profileMissing, notPreRegistered, codeMismatch, unknown }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._auth, this._users, [this._devices]);

  final AuthService _auth;
  final UserRepository _users;
  final DeviceIdentityService? _devices;
  DeviceIdentity? _device;
  bool _binding = false;
  bool _verificationRequested = false;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;

  /// Descarta resultados asíncronos de un usuario anterior.
  int _generation = 0;
  bool _disposed = false;

  AuthStatus _status = AuthStatus.loading;
  User? _firebaseUser;
  AppUser? _profile;
  LinkProblem? _linkProblem;
  bool _linking = false;

  AuthStatus get status => _status;
  AppUser? get profile => _profile;
  String? get email => _firebaseUser?.email;
  LinkProblem? get linkProblem => _linkProblem;
  bool get isLinking => _linking;

  void start() {
    _authSub ??= _auth.authStateChanges().listen(_onAuthChanged);
    _devices?.current().then((device) {
      _device = device;
      final profile = _profile;
      if (profile != null) _onProfile(profile);
      _notify();
    }, onError: (Object _) {});
  }

  /// Este teléfono (identificador de instalación y modelo).
  DeviceIdentity? get device => _device;

  DeviceBinding get deviceBinding {
    final profile = _profile;
    final device = _device;
    if (profile == null ||
        device == null ||
        profile.role != UserRole.student ||
        profile.deviceId == null) {
      return DeviceBinding.unknown;
    }
    return profile.deviceId == device.id
        ? DeviceBinding.thisDevice
        : DeviceBinding.otherDevice;
  }

  /// La primera vez que un estudiante vinculado entra, su cuenta queda atada
  /// a este teléfono.
  Future<void> _bindDeviceIfNeeded(AppUser profile) async {
    final device = _device;
    if (_binding ||
        device == null ||
        profile.role != UserRole.student ||
        !profile.linked ||
        profile.deviceId != null) {
      return;
    }
    _binding = true;
    try {
      await _users.bindDevice(
        uid: profile.uid,
        deviceId: device.id,
        model: device.model,
      );
    } catch (_) {
      // Se reintenta en la próxima actualización del perfil.
    }
    _binding = false;
  }

  Future<void> _onAuthChanged(User? user) async {
    final generation = ++_generation;
    _firebaseUser = user;
    await _profileSub?.cancel();
    if (generation != _generation) return;
    _profileSub = null;
    _profile = null;
    _linkProblem = null;

    if (user == null) {
      _verificationRequested = false;
      _setStatus(AuthStatus.signedOut);
    } else if (!user.emailVerified) {
      _setStatus(AuthStatus.emailNotVerified);
    } else {
      _listenProfile(user.uid);
    }
  }

  void _listenProfile(String uid) {
    _setStatus(AuthStatus.loading);
    _profileSub?.cancel();
    _profileSub = _users
        .watchUser(uid)
        .listen(
          _onProfile,
          onError: (Object _) {
            _linkProblem = LinkProblem.unknown;
            _setStatus(AuthStatus.needsLink);
          },
        );
  }

  void _onProfile(AppUser? profile) {
    _profile = profile;
    if (profile == null) {
      _linkProblem = LinkProblem.profileMissing;
      _setStatus(AuthStatus.needsLink);
    } else if (profile.role == UserRole.teacher) {
      _setStatus(AuthStatus.teacher);
    } else if (profile.linked) {
      _linkProblem = null;
      _setStatus(AuthStatus.student);
      _bindDeviceIfNeeded(profile);
    } else {
      _setStatus(AuthStatus.needsLink);
      if (!_linking && _linkProblem == null) _tryLink();
    }
  }

  Future<void> _tryLink() async {
    final profile = _profile;
    if (profile == null) return;
    final generation = _generation;
    _linking = true;
    _notify();
    LinkProblem? problem;
    try {
      // El token guardado puede ser anterior a la verificación del correo.
      await _auth.refreshToken();
      final pre = await _users.getPreRegistration(profile.email);
      if (pre == null) {
        problem = LinkProblem.notPreRegistered;
      } else if (pre.studentCode != profile.studentCode) {
        problem = LinkProblem.codeMismatch;
      } else {
        // Al actualizarse, el listener del perfil pasa el estado a `student`.
        await _users.markLinked(profile.uid);
      }
    } catch (_) {
      problem = LinkProblem.unknown;
    }
    if (generation != _generation) return;
    _linking = false;
    _linkProblem = problem;
    _notify();
  }

  /// Vuelve a intentar la vinculación (por ejemplo, después de que el docente
  /// agregó al estudiante).
  void retryLink() {
    final user = _firebaseUser;
    if (user == null) return;
    _linkProblem = null;
    _listenProfile(user.uid);
  }

  // --- Acciones de las pantallas. Devuelven un mensaje de error o null. ---

  Future<String?> signIn(String email, String password) =>
      _run(() => _auth.signIn(email, password));

  Future<String?> register({
    required String name,
    required String studentCode,
    required String email,
    required String password,
  }) => _run(() async {
    // Se marca antes de crear la cuenta: el router muestra "Verifica tu
    // correo" apenas existe el usuario, antes de que termine este envío.
    _verificationRequested = true;
    final user = await _auth.register(email, password);
    await _users.createStudentProfile(
      uid: user.uid,
      name: name,
      studentCode: studentCode,
      email: email,
    );
    await _auth.sendEmailVerification();
  });

  Future<String?> resendVerificationEmail() {
    _verificationRequested = true;
    return _run(_auth.sendEmailVerification);
  }

  /// Ya se pidió el correo de verificación en esta sesión. Si no (por ejemplo,
  /// un docente creado en la consola de Firebase, que no envía correos), la
  /// pantalla de verificación lo envía al abrirse.
  bool get verificationEmailRequested => _verificationRequested;

  /// Devuelve `true` si el correo ya fue verificado.
  Future<bool> checkEmailVerified() async {
    try {
      final verified = await _auth.reloadAndCheckVerified();
      if (verified) await _onAuthChanged(_auth.currentUser);
      return verified;
    } catch (_) {
      return false;
    }
  }

  Future<String?> sendPasswordReset(String email) =>
      _run(() => _auth.sendPasswordResetEmail(email));

  Future<void> signOut() => _auth.signOut();

  /// Cambia la contraseña pidiendo la actual (Firebase exige un inicio de
  /// sesión reciente).
  Future<String?> changePassword(String current, String next) async {
    try {
      await _auth.changePassword(current, next);
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return 'La contraseña actual no es correcta.';
      }
      return AuthService.messageFor(e);
    } catch (e) {
      return AuthService.messageFor(e);
    }
  }

  Future<String?> setDefaultPresentMinutes(int minutes) {
    final uid = _profile?.uid;
    if (uid == null) return Future.value(null);
    return _run(() => _users.setDefaultPresentMinutes(uid, minutes));
  }

  /// Elimina una cuenta de estudiante que no llegó a vincularse, para que
  /// pueda registrarse de nuevo. A un docente solo se le cierra la sesión.
  Future<String?> deleteUnlinkedAccount() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final profile = await _users.getUser(user.uid);
      if (profile != null &&
          (profile.role == UserRole.teacher || profile.linked)) {
        await _auth.signOut();
        return null;
      }
      if (profile != null) await _users.deleteProfile(user.uid);
      await _auth.deleteCurrentUser();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        await _auth.signOut();
        return 'Por seguridad, inicia sesión de nuevo y repite la acción.';
      }
      return AuthService.messageFor(e);
    } catch (e) {
      return AuthService.messageFor(e);
    }
  }

  Future<String?> _run(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } catch (e) {
      return AuthService.messageFor(e);
    }
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
