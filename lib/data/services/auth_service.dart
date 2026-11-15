import 'package:firebase_auth/firebase_auth.dart';

/// Envoltura delgada sobre Firebase Authentication.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  Future<User> register(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return credential.user!;
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Recarga el usuario y, si ya verificó el correo, renueva el token para que
  /// las reglas de Firestore vean `email_verified == true`.
  Future<bool> reloadAndCheckVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed == null || !refreshed.emailVerified) return false;
    await refreshed.getIdToken(true);
    return true;
  }

  /// Fuerza un token nuevo para que las reglas vean los datos actuales
  /// (por ejemplo, `email_verified`).
  Future<void> refreshToken() async {
    await _auth.currentUser?.getIdToken(true);
  }

  Future<void> sendPasswordResetEmail(String email) =>
      _auth.sendPasswordResetEmail(email: email);

  Future<void> signOut() => _auth.signOut();

  Future<void> changePassword(String current, String next) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) return;
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: current),
    );
    await user.updatePassword(next);
  }

  Future<void> deleteCurrentUser() async {
    await _auth.currentUser?.delete();
  }

  /// Traduce errores de Firebase a mensajes para el usuario.
  static String messageFor(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
        case 'invalid-login-credentials':
          return 'Correo o contraseña incorrectos.';
        case 'invalid-email':
          return 'El correo no es válido.';
        case 'email-already-in-use':
          return 'Ya existe una cuenta con este correo. Inicia sesión.';
        case 'weak-password':
          return 'La contraseña es demasiado débil.';
        case 'user-disabled':
          return 'Esta cuenta está deshabilitada.';
        case 'too-many-requests':
          return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
        case 'network-request-failed':
          return 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
        case 'requires-recent-login':
          return 'Por seguridad, inicia sesión de nuevo.';
      }
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'permission-denied':
          return 'No tienes permiso para realizar esta acción.';
        case 'unavailable':
          return 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
      }
    }
    return 'Ocurrió un error inesperado. Inténtalo de nuevo.';
  }
}
