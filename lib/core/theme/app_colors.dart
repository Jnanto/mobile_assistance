import 'package:flutter/material.dart';

/// Tokens de color del sistema de diseño "Asist Academic M3".
abstract final class AppColors {
  static const Color primary = Color(0xFF14532D);
  static const Color primaryDark = Color(0xFF003B1B);
  static const Color primaryContainer = Color(0xFFDCFCE7);
  static const Color secondary = Color(0xFF1B6D24);

  static const Color background = Color(0xFFF9FAF7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF3F4F1);
  static const Color surfaceVariant = Color(0xFFF0F2ED);

  static const Color outline = Color(0xFFE2E8F0);

  /// Sombras: azul pizarra muy transparente, como en la guía de diseño.
  static const Color shadow = Color(0x330F172A);

  static const Color surfaceContainerHighest = Color(0xFFE2E3E0);
  static const Color outlineVariant = Color(0xFFCBD5E1);

  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);

  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // Estados de asistencia.
  static const Color present = Color(0xFF2E7D32);
  static const Color presentContainer = Color(0xFFE8F5E9);
  static const Color late = Color(0xFFF59E0B);
  static const Color lateContainer = Color(0xFFFEF3C7);
  static const Color absent = Color(0xFFC62828);
  static const Color absentContainer = Color(0xFFFFEBEE);
  static const Color justified = Color(0xFF1565C0);
  static const Color justifiedContainer = Color(0xFFE3F2FD);
  static const Color tertiary = Color(0xFF492C00);
  static const Color tertiaryContainer = Color(0xFF674000);
  static const Color review = Color(0xFF674000);
  static const Color reviewContainer = Color(0xFFFFDDB8);

  /// Relleno de "Por revisar" en gráficos: el marrón de [review] es muy
  /// oscuro y grisáceo como relleno. Validado junto a los demás estados en
  /// el orden Presente, Por revisar, Tarde, Justificado, Ausente.
  static const Color reviewChart = Color(0xFF8E24AA);

  /// Líneas de cuadrícula de los gráficos.
  static const Color gridLine = Color(0xFFE2E8F0);

  /// Colores que el docente puede elegir para la tarjeta de un curso.
  static const List<Color> courseColors = [
    Color(0xFF14532D),
    Color(0xFF1565C0),
    Color(0xFF6D28D9),
    Color(0xFFB45309),
    Color(0xFFBE185D),
    Color(0xFF0F766E),
  ];

  static Color courseColor(int index) =>
      courseColors[index.clamp(0, courseColors.length - 1)];
}
