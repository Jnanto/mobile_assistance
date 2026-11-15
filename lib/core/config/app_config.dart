/// Parámetros de negocio del proyecto. Ver las decisiones en CLAUDE.md.
abstract final class AppConfig {
  static const String appName = 'SelvaCheck';
  static const String appTagline =
      'Sistema institucional de registro y verificación presencial';
  static const String location = 'Florencia, Caquetá · Colombia';

  /// Dominio de correo permitido para estudiantes. Si se cambia, actualizar
  /// también la función `institutional()` de `firestore.rules`.
  static const String institutionalDomain = 'udla.edu.co';

  /// Límite oficial de la universidad: encuentros por semana de un curso.
  /// Debe coincidir con `firestore.rules`.
  static const int maxMeetingsPerWeek = 2;

  /// Cada cuánto rota el QR dinámico de asistencia.
  static const Duration qrRotation = Duration(seconds: 20);

  /// Un token del QR se acepta hasta este tiempo después de emitido el más
  /// reciente (cubre la latencia entre escanear y enviar). Debe coincidir con
  /// `firestore.rules`.
  static const Duration qrTokenGrace = Duration(seconds: 30);

  /// Ventana para quedar como "Presente" desde el inicio de la clase.
  static const Duration presentWindow = Duration(minutes: 10);

  /// Opciones de tolerancia para "Presente" que el docente puede elegir (D4).
  static const List<int> presentWindowOptions = [5, 10, 15, 20];

  /// Ventana adicional, tras [presentWindow], para quedar como "Tarde".
  static const Duration lateWindow = Duration(minutes: 5);

  /// Margen máximo que se suma al radio por la imprecisión del GPS.
  static const double gpsAccuracyAllowanceMeters = 30;

  /// Máximo de redes WiFi cercanas que guarda el docente al iniciar la clase.
  static const int maxSessionBssids = 30;

  /// Límite de inasistencia. Las llegadas tarde y los justificados no cuentan.
  static const double maxAbsenceRate = 0.20;

  /// Desde esta inasistencia se avisa que el estudiante se acerca al límite.
  static const double absenceWarningRate = 0.15;

  static const int minPasswordLength = 8;

  /// Aviso local antes de cada clase (P1/P2).
  static const int reminderMinutesBefore = 15;

  /// Si la app pasa más de este tiempo en segundo plano, se vuelve a pedir
  /// la huella (cuando el bloqueo está activado).
  static const Duration relockAfter = Duration(minutes: 1);

  /// Sesión de la app: se cierra tras este tiempo sin actividad (toques). La
  /// clase en vivo (D5) la mantiene abierta mientras se proyecta el QR.
  static const Duration sessionTimeout = Duration(minutes: 10);

  static const String appVersion = '1.0.0';

  /// Espera mínima antes de reenviar el correo de verificación.
  static const Duration resendEmailCooldown = Duration(seconds: 60);
}
