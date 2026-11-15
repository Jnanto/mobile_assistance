import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/auth_layout.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../providers/auth_provider.dart';

/// A3 · Verifica tu correo.
///
/// Firebase (plan Spark) verifica con un enlace, no con un código de 6
/// dígitos. La pantalla revisa cada pocos segundos si ya se abrió el enlace.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;
  Timer? _cooldownTimer;
  int _cooldown = AppConfig.resendEmailCooldown.inSeconds;
  bool _checking = false;
  bool _busy = false;
  String? _message;
  BannerKind _messageKind = BannerKind.info;

  @override
  void initState() {
    super.initState();
    _startCooldownTimer();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _check(silent: true));
    // Las cuentas creadas en la consola (docentes) nunca recibieron el correo.
    if (!context.read<AuthProvider>().verificationEmailRequested) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendFirstEmail());
    }
  }

  Future<void> _sendFirstEmail() async {
    final error = await context.read<AuthProvider>().resendVerificationEmail();
    if (!mounted) return;
    setState(() {
      _messageKind = error == null ? BannerKind.success : BannerKind.error;
      _message = error ?? 'Te enviamos el enlace de verificación.';
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _restartCooldown() {
    setState(() => _cooldown = AppConfig.resendEmailCooldown.inSeconds);
    _startCooldownTimer();
  }

  void _startCooldownTimer() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _cooldown--);
      if (_cooldown <= 0) timer.cancel();
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_checking) return;
    _checking = true;
    if (!silent) setState(() => _busy = true);
    final verified = await context.read<AuthProvider>().checkEmailVerified();
    _checking = false;
    // Si ya verificó, el router cambia de pantalla solo.
    if (!mounted || verified || silent) return;
    setState(() {
      _busy = false;
      _messageKind = BannerKind.error;
      _message =
          'Aún no detectamos la verificación. Abre el enlace del '
          'correo y vuelve a intentarlo.';
    });
  }

  Future<void> _resend() async {
    final error = await context.read<AuthProvider>().resendVerificationEmail();
    if (!mounted) return;
    setState(() {
      _messageKind = error == null ? BannerKind.success : BannerKind.error;
      _message = error ?? 'Te enviamos un nuevo enlace de verificación.';
    });
    if (error == null) _restartCooldown();
  }

  Future<void> _useAnotherEmail() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Usar otro correo?'),
        content: const Text(
          'Se eliminará esta cuenta sin verificar para que puedas '
          'registrarte de nuevo con otro correo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar y volver'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final error = await context.read<AuthProvider>().deleteUnlinkedAccount();
    if (!mounted || error == null) return;
    setState(() {
      _messageKind = BannerKind.error;
      _message = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final email = context.select<AuthProvider, String?>((a) => a.email) ?? '';
    final text = Theme.of(context).textTheme;
    return AuthLayout(
      children: [
        AuthHeader(
          icon: Icons.mark_email_read_outlined,
          title: 'Verifica tu correo',
          subtitle:
              'Enviamos un enlace de verificación a '
              '${Formatters.maskEmail(email)}. Ábrelo para confirmar tu '
              'cuenta.',
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Esperando la verificación… Esta pantalla avanzará '
                        'sola cuando abras el enlace.',
                        style: text.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  MessageBanner(_message!, kind: _messageKind),
                ],
                const SizedBox(height: 20),
                LoadingButton(
                  label: 'Ya verifiqué mi correo',
                  icon: Icons.check_circle_outline,
                  loading: _busy,
                  onPressed: _check,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _cooldown > 0 ? null : _resend,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _cooldown > 0
                        ? 'Reenviar en ${Formatters.mmss(_cooldown)}'
                        : 'Reenviar correo',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const FieldHint(
          '¿No te llegó? Revisa la carpeta de spam o correo no deseado.',
          icon: Icons.info_outline,
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _useAnotherEmail,
          child: const Text('Usar otro correo'),
        ),
        TextButton(
          onPressed: () => context.read<AuthProvider>().signOut(),
          child: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
