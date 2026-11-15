import '../config/app_config.dart';

/// Validadores de formularios. Devuelven `null` si el valor es válido o el
/// mensaje de error a mostrar.
abstract final class Validators {
  static final RegExp _institutionalEmail = RegExp(
    '^[^\\s@]+@${RegExp.escape(AppConfig.institutionalDomain)}\$',
  );
  static final RegExp _anyEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _digits = RegExp(r'^[0-9]+$');
  static final RegExp _upper = RegExp('[A-ZÁÉÍÓÚÑ]');
  static final RegExp _number = RegExp('[0-9]');

  /// Normaliza un correo: sin espacios y en minúsculas.
  static String normalizeEmail(String? value) =>
      (value ?? '').trim().toLowerCase();

  static String? institutionalEmail(String? value) {
    final email = normalizeEmail(value);
    if (email.isEmpty) return 'Ingresa tu correo institucional.';
    if (!_anyEmail.hasMatch(email)) return 'Ingresa un correo válido.';
    if (!_institutionalEmail.hasMatch(email)) {
      return 'Solo se admiten correos @${AppConfig.institutionalDomain}.';
    }
    return null;
  }

  /// Para el inicio de sesión: los docentes pueden tener otro dominio.
  static String? email(String? value) {
    final email = normalizeEmail(value);
    if (email.isEmpty) return 'Ingresa tu correo.';
    if (!_anyEmail.hasMatch(email)) return 'Ingresa un correo válido.';
    return null;
  }

  static String? fullName(String? value) {
    final words = (value ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return 'Ingresa tu nombre completo.';
    if (words.length < 2) return 'Ingresa al menos un nombre y un apellido.';
    if (value!.trim().length > 120) return 'El nombre es demasiado largo.';
    return null;
  }

  static String? studentCode(String? value) {
    final code = (value ?? '').trim();
    if (code.isEmpty) return 'Ingresa tu código estudiantil.';
    if (!_digits.hasMatch(code)) return 'El código solo debe contener números.';
    if (code.length < 6 || code.length > 12) {
      return 'El código debe tener entre 6 y 12 dígitos.';
    }
    return null;
  }

  /// Teléfono opcional: de 7 a 15 dígitos; admite espacios, guiones y "+".
  static String? optionalPhone(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!RegExp(r'^[0-9 +()-]+$').hasMatch(text)) {
      return 'Solo números, espacios, "+" o guiones.';
    }
    final digits = text.replaceAll(RegExp('[^0-9]'), '').length;
    if (digits < 7 || digits > 15) return 'Debe tener entre 7 y 15 dígitos.';
    return null;
  }

  /// Texto opcional de hasta [max] caracteres.
  static String? optionalText(String? value, {int max = 80}) =>
      (value ?? '').trim().length > max ? 'Máximo $max caracteres.' : null;

  static String? loginPassword(String? value) =>
      (value ?? '').isEmpty ? 'Ingresa tu contraseña.' : null;

  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.length < AppConfig.minPasswordLength) {
      return 'Mínimo ${AppConfig.minPasswordLength} caracteres.';
    }
    if (!_upper.hasMatch(password) || !_number.hasMatch(password)) {
      return 'Debe tener al menos una mayúscula y un número.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Confirma tu contraseña.';
    if (value != original) return 'Las contraseñas no coinciden.';
    return null;
  }

  /// Cuántos requisitos de contraseña se cumplen (0 a 3): longitud,
  /// mayúscula y número.
  static int passwordScore(String password) {
    var score = 0;
    if (password.length >= AppConfig.minPasswordLength) score++;
    if (_upper.hasMatch(password)) score++;
    if (_number.hasMatch(password)) score++;
    return score;
  }
}
