import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/auth_layout.dart';
import '../auth/providers/auth_provider.dart';
import 'profile_controllers.dart';

/// Cubre la app con una pantalla de bloqueo cuando el usuario activó el
/// desbloqueo con huella.
class AppLockGate extends StatelessWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    final status = context.select<AuthProvider, AuthStatus>((a) => a.status);
    final signedIn =
        status == AuthStatus.teacher || status == AuthStatus.student;
    return Stack(
      children: [
        child,
        if (signedIn && lock.locked)
          const Positioned.fill(child: _LockScreen()),
      ],
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen();

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    final ok = await context.read<AppLockController>().unlock();
    if (mounted && !ok) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.background,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandBadge(size: 72),
                const SizedBox(height: 24),
                Text(
                  '${AppConfig.appName} está bloqueado',
                  style: text.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _failed
                      ? 'No se pudo verificar. Inténtalo de nuevo.'
                      : 'Usa tu huella o el bloqueo de tu teléfono.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Desbloquear'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
