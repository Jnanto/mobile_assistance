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
import '../providers/session_controller.dart';
import '../../../shared/widgets/visual_widgets.dart';

/// A1 · Iniciar sesión.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await context.read<AuthProvider>().signIn(
      Validators.normalizeEmail(_email.text),
      _password.text,
    );
    // Si el inicio de sesión funciona, el router cambia de pantalla solo.
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
      children: [
        Card(
          color: AppColors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const BrandBadge(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppConfig.appName, style: text.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        AppConfig.appTagline,
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Bienvenido', style: text.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Ingresa con tus credenciales institucionales.',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (context.select<SessionController, bool>(
                      (s) => s.expiredByInactivity,
                    )) ...[
                      const SizedBox(height: 16),
                      NoticeBox(
                        icon: Icons.lock_clock,
                        color: AppColors.justified,
                        background: AppColors.justifiedContainer,
                        title: 'Tu sesión se cerró',
                        child: Text(
                          'Pasaron '
                          '${AppConfig.sessionTimeout.inMinutes} minutos sin '
                          'actividad. Vuelve a ingresar para continuar.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const FieldLabel('Correo institucional'),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: Validators.email,
                      decoration: const InputDecoration(
                        hintText: 'usuario@${AppConfig.institutionalDomain}',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const FieldHint(
                      'Usa tu cuenta con dominio institucional '
                      '@${AppConfig.institutionalDomain}',
                    ),
                    const SizedBox(height: 16),
                    const FieldLabel('Contraseña'),
                    PasswordField(
                      controller: _password,
                      validator: Validators.loginPassword,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push(Routes.forgotPassword),
                        child: const Text('¿Olvidaste tu contraseña?'),
                      ),
                    ),
                    if (_error != null) ...[
                      MessageBanner(_error!),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 8),
                    LoadingButton(
                      label: 'Ingresar',
                      loading: _loading,
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: AppColors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Text(
                  '¿Nuevo por acá?',
                  style: text.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push(Routes.register),
                  child: const Text('Crea tu cuenta estudiantil'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        const LocationFooter(),
      ],
    );
  }
}
