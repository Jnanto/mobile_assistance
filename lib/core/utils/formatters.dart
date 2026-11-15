abstract final class Formatters {
  /// Oculta parte del correo: `lmendez@udla.edu.co` → `l•••@udla.edu.co`.
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    return '${email[0]}•••${email.substring(at)}';
  }

  /// `65` segundos → `01:05`.
  static String mmss(int totalSeconds) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = (s ~/ 60).toString().padLeft(2, '0');
    final seconds = (s % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
