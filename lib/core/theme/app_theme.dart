import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_motion.dart';

abstract final class AppTheme {
  static const double radiusField = 12;
  static const double radiusCard = 16;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primaryDark,
      secondary: AppColors.secondary,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainerHighest: AppColors.surfaceVariant,
      outline: AppColors.outlineVariant,
      outlineVariant: AppColors.outline,
      error: AppColors.error,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
    );

    // Roboto es la fuente del sistema en Android; se nombra para que todos
    // los estilos (también los de botones) la usen de forma explícita.
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
    );
    // Escala tipográfica de la guía "Asist Academic M3" (DESIGN.md).
    TextStyle? style(
      TextStyle? from,
      double size,
      FontWeight weight, {
      double height = 1.4,
      double spacing = 0,
    }) => from?.copyWith(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: AppColors.textPrimary,
    );
    final t = base.textTheme;
    final textTheme = t
        .apply(
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        )
        .copyWith(
          headlineLarge: style(
            t.headlineLarge,
            28,
            FontWeight.w600,
            height: 1.3,
          ),
          headlineMedium: style(
            t.headlineMedium,
            24,
            FontWeight.w600,
            height: 1.33,
          ),
          headlineSmall: style(
            t.headlineSmall,
            20,
            FontWeight.w700,
            height: 1.4,
          ),
          titleLarge: style(t.titleLarge, 18, FontWeight.w700, height: 1.35),
          titleMedium: style(
            t.titleMedium,
            16,
            FontWeight.w600,
            height: 1.5,
            spacing: 0.16,
          ),
          titleSmall: style(t.titleSmall, 14, FontWeight.w600, height: 1.43),
          bodyLarge: style(t.bodyLarge, 16, FontWeight.w400, height: 1.5),
          bodyMedium: style(t.bodyMedium, 14, FontWeight.w400, height: 1.43),
          bodySmall: style(t.bodySmall, 12, FontWeight.w400, height: 1.33),
          labelLarge: style(
            t.labelLarge,
            14,
            FontWeight.w600,
            height: 1.43,
            spacing: 0.14,
          ),
          labelMedium: style(
            t.labelMedium,
            12,
            FontWeight.w600,
            height: 1.33,
            spacing: 0.24,
          ),
          labelSmall: style(
            t.labelSmall,
            11,
            FontWeight.w500,
            height: 1.27,
            spacing: 0.33,
          ),
        );

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusCard),
      borderSide: width == 0
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusCard),
    );
    const buttonText = TextStyle(
      fontFamily: 'Roboto',
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      // Barra superior blanca con sombra suave y título centrado.
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        scrolledUnderElevation: 1,
        shadowColor: AppColors.shadow,
        centerTitle: true,
        toolbarHeight: 64,
        titleTextStyle: textTheme.titleMedium,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: AppColors.shadow,
        indicatorColor: AppColors.primaryContainer,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryDark
                : AppColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.primaryDark
                : AppColors.textSecondary,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 4,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
        extendedTextStyle: buttonText,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        border: border(Colors.transparent, 0),
        enabledBorder: border(Colors.transparent, 0),
        focusedBorder: border(AppColors.primary, 2),
        errorBorder: border(AppColors.error, 1.5),
        focusedErrorBorder: border(AppColors.error, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: buttonShape,
          textStyle: buttonText,
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // Nivel 1 de la guía: blanco, borde muy suave y sombra difusa.
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: AppColors.shadow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: textTheme.titleSmall?.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
        ),
        iconColor: AppColors.primaryDark,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: SelvaPageTransitionsBuilder(),
          TargetPlatform.iOS: SelvaPageTransitionsBuilder(),
          TargetPlatform.linux: SelvaPageTransitionsBuilder(),
          TargetPlatform.windows: SelvaPageTransitionsBuilder(),
          TargetPlatform.macOS: SelvaPageTransitionsBuilder(),
        },
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.outlineVariant,
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
