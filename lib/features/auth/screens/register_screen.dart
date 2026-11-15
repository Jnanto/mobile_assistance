import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/auth_layout.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../providers/auth_provider.dart';

/// A2 · Crear cuenta estudiantil.
///
/// Solo funciona para estudiantes que un docente agregó antes (pre-registro).
/// La vinculación se comprueba después de verificar el correo.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _acceptedPolicy = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final valid = _formKey.currentState!.validate();
    if (!_acceptedPolicy) {
      setState(
        () => _error =
            'Debes aceptar la política de tratamiento de datos personales.',
      );
      return;
    }
    if (!valid) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await context.read<AuthProvider>().register(
      name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      studentCode: _code.text.trim(),
      email: Validators.normalizeEmail(_email.text),
      password: _password.text,
    );
    // Si el registro funciona, el router lleva a "Verifica tu correo".
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      showBack: true,
      children: [
        const BrandPill(),
        const SizedBox(height: 10),
        Text(
          'Crear cuenta estudiantil',
          style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Ingresa tus datos para registrarte.',
          style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        const MessageBanner(
          'Solo pueden crear cuenta los estudiantes que un docente agregó a '
          'un curso. Usa el mismo correo y código que registró tu docente.',
          kind: BannerKind.info,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FieldLabel('Nombre completo', trailing: 'Requerido'),
                    TextFormField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: Validators.fullName,
                      decoration: const InputDecoration(
                        hintText: 'Nombres y apellidos',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder(
                      valueListenable: _code,
                      builder: (context, value, _) {
                        final code = value.text.trim();
                        final ok = Validators.studentCode(code) == null;
                        return FieldLabel(
                          'Código estudiantil',
                          trailing: ok
                              ? '${code.length} dígitos'
                              : 'Solo números',
                          trailingColor: ok
                              ? AppColors.present
                              : AppColors.textMuted,
                        );
                      },
                    ),
                    TextFormField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      validator: Validators.studentCode,
                      decoration: const InputDecoration(
                        hintText: 'Ej. 20231145028',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ValueListenableBuilder(
                      valueListenable: _email,
                      builder: (context, value, _) =>
                          Validators.institutionalEmail(value.text) == null
                          ? const FieldLabel(
                              'Correo institucional',
                              trailing: 'Válido',
                              trailingIcon: Icons.check_circle_outline,
                              trailingColor: AppColors.present,
                            )
                          : const FieldLabel('Correo institucional'),
                    ),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: Validators.institutionalEmail,
                      decoration: const InputDecoration(
                        hintText: 'usuario@${AppConfig.institutionalDomain}',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const FieldHint(
                      'Solo se admiten correos con dominio '
                      '@${AppConfig.institutionalDomain}',
                      icon: Icons.info_outline,
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Contraseña'),
                    PasswordField(
                      controller: _password,
                      validator: Validators.newPassword,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                    ),
                    PasswordStrengthBar(controller: _password),
                    const SizedBox(height: 16),
                    const FieldLabel('Confirmar contraseña'),
                    PasswordField(
                      controller: _confirm,
                      prefixIcon: Icons.lock_reset,
                      validator: (v) =>
                          Validators.confirmPassword(v, _password.text),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _acceptedPolicy,
                      onChanged: (v) =>
                          setState(() => _acceptedPolicy = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        'Acepto la política de tratamiento de datos '
                        'personales.',
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      MessageBanner(_error!),
                    ],
                    const SizedBox(height: 16),
                    LoadingButton(
                      label: 'Crear cuenta',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '¿Ya tienes cuenta?',
              style: text.bodyLarge?.copyWith(color: AppColors.textSecondary),
            ),
            TextButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(Routes.login),
              child: const Text('Iniciar sesión'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const LocationFooter(),
      ],
    );
  }
}
