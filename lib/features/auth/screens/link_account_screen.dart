import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/auth_layout.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../providers/auth_provider.dart';

/// Vincula la cuenta del estudiante con el pre-registro que hizo su docente.
/// No existe en los mockups; aparece solo si algo impide la vinculación.
class LinkAccountScreen extends StatefulWidget {
  const LinkAccountScreen({super.key});

  @override
  State<LinkAccountScreen> createState() => _LinkAccountScreenState();
}

class _LinkAccountScreenState extends State<LinkAccountScreen> {
  bool _deleting = false;
  String? _error;

  static String _messageFor(LinkProblem problem) => switch (problem) {
    LinkProblem.notPreRegistered =>
      'Tu correo aún no ha sido agregado por ningún docente. Pídele a tu '
          'docente que te agregue al curso y luego toca "Reintentar".',
    LinkProblem.codeMismatch =>
      'El código estudiantil que ingresaste no coincide con el que '
          'registró tu docente. Elimina la cuenta y regístrate de nuevo '
          'con el código correcto, o pide a tu docente que lo corrija.',
    LinkProblem.profileMissing =>
      'No encontramos los datos de tu cuenta. Elimínala y regístrate de '
          'nuevo.',
    LinkProblem.unknown =>
      'No pudimos vincular tu cuenta. Revisa tu conexión e inténtalo de '
          'nuevo.',
  };

  Future<void> _deleteAndRestart() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    final error = await context.read<AuthProvider>().deleteUnlinkedAccount();
    if (!mounted) return;
    setState(() {
      _deleting = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final problem = auth.linkProblem;

    if (problem == null || auth.isLinking) {
      return const AuthLayout(
        children: [
          AuthHeader(
            icon: Icons.link,
            title: 'Vinculando tu cuenta',
            subtitle: 'Estamos comprobando que tu docente te haya agregado.',
          ),
          SizedBox(height: 32),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final canRetry =
        problem == LinkProblem.notPreRegistered ||
        problem == LinkProblem.unknown ||
        problem == LinkProblem.codeMismatch;
    final canDelete = problem != LinkProblem.unknown;

    return AuthLayout(
      children: [
        const AuthHeader(
          icon: Icons.link_off,
          title: 'No pudimos vincular tu cuenta',
          subtitle: 'Tu correo ya está verificado, pero falta un paso.',
        ),
        const SizedBox(height: 24),
        MessageBanner(_messageFor(problem), kind: BannerKind.info),
        if (_error != null) ...[
          const SizedBox(height: 12),
          MessageBanner(_error!),
        ],
        const SizedBox(height: 24),
        if (canRetry)
          LoadingButton(
            label: 'Reintentar',
            icon: Icons.refresh,
            onPressed: auth.retryLink,
          ),
        if (canDelete) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _deleting ? null : _deleteAndRestart,
            child: const Text('Eliminar cuenta y registrarme de nuevo'),
          ),
        ],
        const SizedBox(height: 12),
        TextButton(onPressed: auth.signOut, child: const Text('Cerrar sesión')),
      ],
    );
  }
}
