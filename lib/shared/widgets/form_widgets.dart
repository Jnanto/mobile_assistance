import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';

/// Etiqueta encima de un campo, con un texto opcional a la derecha.
class FieldLabel extends StatelessWidget {
  const FieldLabel(
    this.text, {
    super.key,
    this.trailing,
    this.trailingColor = AppColors.textMuted,
    this.trailingIcon,
  });

  final String text;
  final String? trailing;
  final Color trailingColor;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: style?.copyWith(color: AppColors.textPrimary),
            ),
          ),
          if (trailingIcon != null) ...[
            Icon(trailingIcon, size: 16, color: trailingColor),
            const SizedBox(width: 4),
          ],
          if (trailing != null)
            Text(
              trailing!,
              style: style?.copyWith(
                color: trailingColor,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// Texto de ayuda pequeño debajo de un campo.
class FieldHint extends StatelessWidget {
  const FieldHint(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: AppColors.textMuted);
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// Campo de contraseña con botón para mostrar u ocultar.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.validator,
    this.hintText = '••••••••',
    this.prefixIcon = Icons.lock_outline,
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final String hintText;
  final IconData prefixIcon;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      autofillHints: widget.autofillHints,
      decoration: InputDecoration(
        hintText: widget.hintText,
        prefixIcon: Icon(widget.prefixIcon),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Barra de 3 segmentos que muestra cuántos requisitos cumple la contraseña.
class PasswordStrengthBar extends StatelessWidget {
  const PasswordStrengthBar({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final score = Validators.passwordScore(value.text);
        return Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Mínimo 8 caracteres, una mayúscula y un número',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.textMuted),
                ),
              ),
              for (var i = 0; i < 3; i++)
                Container(
                  width: 28,
                  height: 4,
                  margin: const EdgeInsets.only(left: 4),
                  decoration: BoxDecoration(
                    color: i < score ? AppColors.present : AppColors.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Botón principal que muestra un indicador mientras [loading] es true.
class LoadingButton extends StatelessWidget {
  const LoadingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon = Icons.arrow_forward,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 20),
                ],
              ],
            ),
    );
  }
}

enum BannerKind { error, info, success }

/// Mensaje destacado de error, información o éxito.
class MessageBanner extends StatelessWidget {
  const MessageBanner(this.message, {super.key, this.kind = BannerKind.error});

  final String message;
  final BannerKind kind;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, IconData icon) = switch (kind) {
      BannerKind.error => (
        AppColors.onErrorContainer,
        AppColors.errorContainer,
        Icons.error_outline,
      ),
      BannerKind.info => (
        AppColors.justified,
        AppColors.justifiedContainer,
        Icons.info_outline,
      ),
      BannerKind.success => (
        AppColors.present,
        AppColors.presentContainer,
        Icons.check_circle_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
