import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/auth_layout.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../providers/auth_provider.dart';

/// A4 · Recuperar contraseña.
///
/// Firebase envía un enlace; la nueva contraseña se define en la página que
/// abre ese enlace (reemplaza a la pantalla A4b del mockup).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await context.read<AuthProvider>().sendPasswordReset(
      Validators.normalizeEmail(_email.text),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
      _sent = error == null;
    });
  }

  void _backToLogin() =>
      context.canPop() ? context.pop() : context.go(Routes.login);

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      showBack: true,
      children: [
        const AuthHeader(
          icon: Icons.lock_reset,
          title: '¿Olvidaste tu contraseña?',
          subtitle:
              'Ingresa tu correo registrado y te enviaremos un enlace '
              'para crear una nueva contraseña.',
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel(
                    'Correo institucional',
                    trailing: 'Requerido',
                    trailingColor: AppColors.present,
                  ),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: 'usuario@${AppConfig.institutionalDomain}',
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                  ),
                  if (_sent) ...[
                    const SizedBox(height: 16),
                    const MessageBanner(
                      'Si el correo está registrado, recibirás un enlace '
                      'para restablecer tu contraseña. Revisa también la '
                      'carpeta de spam.',
                      kind: BannerKind.success,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    MessageBanner(_error!),
                  ],
                  const SizedBox(height: 20),
                  LoadingButton(
                    label: _sent ? 'Reenviar enlace' : 'Enviar enlace',
                    icon: Icons.send_outlined,
                    loading: _loading,
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    onPressed: _backToLogin,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Regresar al inicio de sesión'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(
                icon: Icons.contact_support_outlined,
                color: AppColors.primaryDark,
                background: AppColors.surface,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¿Problemas con tu correo?',
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Si olvidaste tu correo institucional o tu cuenta no '
                      'funciona, comunícate con tu docente o con la mesa de '
                      'ayuda de la universidad.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
