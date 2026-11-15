import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_motion.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/schedule_format.dart';
import '../../core/utils/validators.dart';
import '../../data/models/app_user.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/auth_service.dart';
import '../../data/services/report_export.dart';
import '../../shared/widgets/common_widgets.dart';
import '../../shared/widgets/form_widgets.dart';
import '../auth/providers/auth_provider.dart';
import 'profile_controllers.dart';
import 'profile_photos.dart';

/// P1 / P2 · Perfil. [roleSections] agrega lo propio de cada rol (por
/// ejemplo, las cifras y la tolerancia del docente).
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key, this.roleSections = const [], this.heroFooter});

  final List<Widget> roleSections;

  /// Contenido al pie de la tarjeta verde (cifras del docente). Si es nulo,
  /// se muestran el código y el programa del estudiante.
  final Widget? heroFooter;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final text = Theme.of(context).textTheme;
    if (profile == null) return const SizedBox.shrink();
    final isTeacher = profile.role == UserRole.teacher;
    final initials = profile.name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: staggered([
        _ProfileHero(
          profile: profile,
          initials: initials,
          footer:
              heroFooter ??
              _StudentHeroFooter(
                code: profile.studentCode ?? '',
                program: profile.program,
              ),
        ),
        const _SectionLabel('Información personal', icon: Icons.badge_outlined),
        _PersonalDataCard(profile: profile),
        ...roleSections,
        const _SectionLabel(
          'Seguridad y dispositivo',
          icon: Icons.shield_outlined,
        ),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const ProfileIcon(Icons.lock_reset),
                title: const Text('Cambiar contraseña'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => const ChangePasswordSheet(),
                ),
              ),
              const Divider(height: 1),
              _DeviceTile(isTeacher: isTeacher),
              const Divider(height: 1),
              const _BiometricTile(),
            ],
          ),
        ),
        const _SectionLabel('Notificaciones', icon: Icons.notifications_none),
        const Card(child: _RemindersTile()),
        const _SectionLabel('Configuración y soporte', icon: Icons.tune),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const ProfileIcon(Icons.gavel_outlined),
                title: const Text('Reglamento de asistencia'),
                subtitle: const Text(
                  'Tolerancias, límite de faltas y revisión',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showAttendanceRules(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const ProfileIcon(Icons.support_agent),
                title: const Text('¿Problemas con tu cuenta?'),
                subtitle: Text(
                  isTeacher
                      ? 'Contacta a quien administra SelvaCheck en tu facultad.'
                      : 'Habla con tu docente: puede corregir tus datos, tu '
                            'asistencia o desvincular tu teléfono.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.absentContainer,
            foregroundColor: AppColors.absent,
            elevation: 0,
          ),
          onPressed: () async {
            await context.read<RemindersController>().clear();
            await auth.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.present,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${AppConfig.appName} v${AppConfig.appVersion}',
              style: text.labelSmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Universidad de la Amazonia · Florencia, Caquetá',
          style: text.labelSmall?.copyWith(color: AppColors.textMuted),
          textAlign: TextAlign.center,
        ),
      ]),
    );
  }
}

/// Tarjeta verde con la identidad del usuario.
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.profile,
    required this.initials,
    required this.footer,
  });

  final AppUser profile;
  final String initials;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final isTeacher = profile.role == UserRole.teacher;
    const mint = Color(0xFFA3F69C);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7D32), AppColors.primaryDark],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Cambiar foto de perfil',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => showPhotoSheet(context, profile.email),
                  child: SizedBox(
                    width: 68,
                    height: 68,
                    child: Stack(
                      children: [
                        PhotoOrInitials(
                          name: profile.name,
                          email: profile.email,
                          size: 64,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.present,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(
                              Icons.photo_camera,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTeacher ? 'PERFIL DOCENTE' : 'PERFIL INSTITUCIONAL',
                      style: text.labelSmall?.copyWith(
                        color: mint,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      isTeacher ? 'Prof. ${profile.name}' : profile.name,
                      style: text.headlineSmall?.copyWith(color: Colors.white),
                    ),
                    Text(
                      profile.email,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatusChip(
            label: isTeacher ? 'Docente' : 'Estudiante activo',
            dot: true,
            foreground: Colors.white,
            background: Colors.white.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: footer,
          ),
        ],
      ),
    );
  }
}

/// Pie de la tarjeta del estudiante: código y programa.
class _StudentHeroFooter extends StatelessWidget {
  const _StudentHeroFooter({required this.code, required this.program});

  final String code;
  final String program;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget column(String label, String value, CrossAxisAlignment align) =>
        Column(
          crossAxisAlignment: align,
          children: [
            Text(
              label,
              style: text.labelSmall?.copyWith(color: Colors.white70),
            ),
            Text(
              value,
              textAlign: align == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
              style: text.titleSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    return Row(
      children: [
        Expanded(
          child: column(
            'Código estudiantil',
            code.isEmpty ? '—' : code,
            CrossAxisAlignment.start,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: column(
            'Programa',
            program.trim().isEmpty ? 'Sin registrar' : program,
            CrossAxisAlignment.end,
          ),
        ),
      ],
    );
  }
}

/// Ícono de una fila del perfil, dentro de un círculo gris.
class ProfileIcon extends StatelessWidget {
  const ProfileIcon(this.icon, {super.key, this.color = AppColors.primaryDark});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariant,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.primaryDark),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.isTeacher});

  final bool isTeacher;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final model = auth.device?.model ?? 'Este teléfono';
    if (isTeacher) {
      return ListTile(
        leading: const ProfileIcon(Icons.smartphone),
        title: Text(model),
        subtitle: const Text('Teléfono actual'),
      );
    }
    final profile = auth.profile;
    final boundAt = profile?.deviceBoundAt;
    return switch (auth.deviceBinding) {
      DeviceBinding.thisDevice => ListTile(
        leading: const ProfileIcon(Icons.smartphone),
        title: Text(model),
        subtitle: Text(
          boundAt == null
              ? 'Tu cuenta está vinculada a este teléfono.'
              : 'Vinculado desde el ${ScheduleFormat.date(boundAt).toLowerCase()}.',
        ),
        trailing: const StatusChip(
          label: 'Autorizado',
          icon: Icons.verified_user_outlined,
          foreground: AppColors.present,
          background: AppColors.presentContainer,
        ),
      ),
      DeviceBinding.otherDevice => ListTile(
        leading: const ProfileIcon(
          Icons.phonelink_lock,
          color: AppColors.absent,
        ),
        title: const Text('Vinculada a otro teléfono'),
        subtitle: Text(
          '${profile?.deviceModel ?? 'Otro teléfono'}. Desde este no podrás '
          'marcar asistencia; pide a tu docente que la desvincule.',
        ),
      ),
      DeviceBinding.unknown => ListTile(
        leading: const ProfileIcon(Icons.smartphone),
        title: Text(model),
        subtitle: const Text('Vinculando tu cuenta con este teléfono…'),
      ),
    };
  }
}

class _BiometricTile extends StatelessWidget {
  const _BiometricTile();

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockController>();
    return SwitchListTile(
      secondary: const ProfileIcon(Icons.fingerprint),
      title: const Text('Desbloqueo con huella'),
      subtitle: const Text('Pide tu huella o el PIN del teléfono al abrir.'),
      value: lock.enabled,
      onChanged: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final error = await lock.setEnabled(value);
        if (error != null) {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );
  }
}

class _RemindersTile extends StatelessWidget {
  const _RemindersTile();

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<RemindersController>();
    final minutes = AppConfig.reminderMinutesBefore;
    return SwitchListTile(
      secondary: const ProfileIcon(Icons.notifications_active_outlined),
      title: const Text('Avisos de clase'),
      subtitle: Text(
        reminders.enabled
            ? '$minutes min antes de cada clase · '
                  '${reminders.count} avisos por semana'
            : '$minutes min antes de cada clase',
      ),
      value: reminders.enabled,
      onChanged: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final error = await reminders.setEnabled(value);
        if (error != null) {
          messenger.showSnackBar(SnackBar(content: Text(error)));
        }
      },
    );
  }
}

/// Reglamento de asistencia, con los valores configurados en la app.
void showAttendanceRules(BuildContext context) {
  final present = AppConfig.presentWindow.inMinutes;
  final late = AppConfig.lateWindow.inMinutes;
  final limit = percent(AppConfig.maxAbsenceRate);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reglamento de asistencia'),
      content: SingleChildScrollView(
        child: Text(
          '• Al iniciar la clase hay $present minutos (por defecto) para '
          'quedar como "Presente" y $late minutos más para quedar como '
          '"Tarde". Después, quien no marcó queda "Ausente".\n\n'
          '• Para marcar se necesita el código QR que muestra el docente '
          '(cambia cada ${AppConfig.qrRotation.inSeconds} segundos), estar '
          'dentro del aula según el GPS y conectado al WiFi del aula.\n\n'
          '• Si falla el GPS o el WiFi, el registro queda "Por revisar" y el '
          'docente lo aprueba o lo rechaza.\n\n'
          '• Solo se puede marcar desde el teléfono vinculado a la cuenta.\n\n'
          '• El límite de inasistencia es del $limit de las clases dictadas. '
          'Las llegadas tarde y las faltas justificadas no cuentan como '
          'inasistencia.\n\n'
          '• El docente puede corregir un registro o justificar una falta '
          'indicando el motivo.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}

/// Cambio de contraseña (pide la actual).
class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final error = await context.read<AuthProvider>().changePassword(
      _current.text,
      _next.text,
    );
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Tu contraseña se actualizó.')),
      );
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cambiar contraseña', style: text.titleLarge),
                const SizedBox(height: 16),
                const FieldLabel('Contraseña actual'),
                PasswordField(
                  controller: _current,
                  validator: Validators.loginPassword,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                const FieldLabel('Nueva contraseña'),
                PasswordField(
                  controller: _next,
                  validator: Validators.newPassword,
                  textInputAction: TextInputAction.next,
                ),
                PasswordStrengthBar(controller: _next),
                const SizedBox(height: 12),
                const FieldLabel('Confirmar nueva contraseña'),
                PasswordField(
                  controller: _confirm,
                  prefixIcon: Icons.lock_reset,
                  validator: (v) => Validators.confirmPassword(v, _next.text),
                  onFieldSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(_error!),
                ],
                const SizedBox(height: 16),
                LoadingButton(
                  label: 'Guardar contraseña',
                  icon: Icons.save_outlined,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Datos personales y académicos, con el botón para editarlos.
class _PersonalDataCard extends StatelessWidget {
  const _PersonalDataCard({required this.profile});

  final AppUser profile;

  @override
  Widget build(BuildContext context) {
    final isTeacher = profile.role == UserRole.teacher;
    String orDash(String value) =>
        value.trim().isEmpty ? 'Sin registrar' : value;
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const ProfileIcon(Icons.photo_camera_outlined),
            title: const Text('Foto de perfil'),
            subtitle: Text(
              context.select<PhotoCache, bool>(
                    (c) => c.photoOf(profile.email) != null,
                  )
                  ? 'Cámbiala o quítala cuando quieras'
                  : 'Sin foto: se muestran tus iniciales',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showPhotoSheet(context, profile.email),
          ),
          ListTile(
            leading: const ProfileIcon(Icons.phone_outlined),
            title: const Text('Teléfono'),
            subtitle: Text(orDash(profile.phone)),
          ),
          ListTile(
            leading: ProfileIcon(
              isTeacher
                  ? Icons.account_balance_outlined
                  : Icons.school_outlined,
            ),
            title: Text(
              isTeacher ? 'Facultad o dependencia' : 'Programa académico',
            ),
            subtitle: Text(
              orDash(isTeacher ? profile.department : profile.program),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const ProfileIcon(Icons.edit_outlined),
            title: const Text('Editar perfil'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => EditProfileSheet(profile: profile),
            ),
          ),
        ],
      ),
    );
  }
}

/// Edición del perfil: nombre, teléfono y programa (estudiante) o
/// dependencia (docente). El correo y el código no se editan.
class EditProfileSheet extends StatefulWidget {
  const EditProfileSheet({super.key, required this.profile});

  final AppUser profile;

  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile.name);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _academic = TextEditingController(
    text: _isTeacher ? widget.profile.department : widget.profile.program,
  );
  bool _saving = false;
  String? _error;

  bool get _isTeacher => widget.profile.role == UserRole.teacher;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _academic.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final name = _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final users = context.read<UserRepository>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await users.updateProfile(
        uid: widget.profile.uid,
        name: name,
        phone: _phone.text.trim(),
        program: _isTeacher ? null : _academic.text.trim(),
        department: _isTeacher ? _academic.text.trim() : null,
        // Los cursos guardan una copia del nombre del docente.
        renameInCourses: _isTeacher && name != widget.profile.name,
      );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Tu perfil se actualizó.')),
      );
      return;
    } catch (e) {
      _error = AuthService.messageFor(e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profile = widget.profile;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Editar perfil', style: text.titleLarge),
                const SizedBox(height: 16),
                const FieldLabel('Nombre completo'),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  validator: Validators.fullName,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                if (!_isTeacher)
                  const FieldHint(
                    'Así te verás en la app. En las listas de cada curso '
                    'aparece el nombre que registró tu docente.',
                    icon: Icons.info_outline,
                  ),
                const SizedBox(height: 12),
                const FieldLabel('Teléfono'),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  validator: Validators.optionalPhone,
                  decoration: const InputDecoration(
                    hintText: 'Ej. 310 123 4567',
                    prefixIcon: Icon(Icons.phone_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                FieldLabel(
                  _isTeacher ? 'Facultad o dependencia' : 'Programa académico',
                ),
                TextFormField(
                  controller: _academic,
                  textCapitalization: TextCapitalization.sentences,
                  validator: Validators.optionalText,
                  decoration: InputDecoration(
                    hintText: _isTeacher
                        ? 'Ej. Facultad de Ingeniería'
                        : 'Ej. Ingeniería de Sistemas',
                    prefixIcon: const Icon(Icons.school_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                MessageBanner(
                  _isTeacher
                      ? 'El correo (${profile.email}) identifica tu cuenta y '
                            'no se puede cambiar desde la app.'
                      : 'El correo (${profile.email}) y el código '
                            '(${profile.studentCode ?? ''}) identifican tu '
                            'cuenta. Si están mal, pide a tu docente que los '
                            'corrija.',
                  kind: BannerKind.info,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(_error!),
                ],
                const SizedBox(height: 16),
                LoadingButton(
                  label: 'Guardar cambios',
                  icon: Icons.save_outlined,
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre la hoja para tomar, elegir o quitar la foto de perfil.
Future<void> showPhotoSheet(BuildContext context, String email) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _PhotoSheet(email: email),
    );

class _PhotoSheet extends StatefulWidget {
  const _PhotoSheet({required this.email});

  final String email;

  @override
  State<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends State<_PhotoSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      return;
    } on ArgumentError {
      _error =
          'La foto es demasiado pesada. Prueba con otra o tómala de nuevo.';
    } catch (e) {
      _error = AuthService.messageFor(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pick(bool fromCamera) async {
    final picker = context.read<PhotoPicker>();
    final cache = context.read<PhotoCache>();
    Uint8List? bytes;
    try {
      bytes = await picker.pick(fromCamera: fromCamera);
    } catch (_) {
      setState(
        () => _error = fromCamera
            ? 'No se pudo abrir la cámara. Revisa el permiso de cámara.'
            : 'No se pudo abrir la galería.',
      );
      return;
    }
    if (bytes == null || !mounted) return;
    final photo = bytes;
    await _run(() => cache.save(widget.email, photo), 'Foto actualizada.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasPhoto = context.select<PhotoCache, bool>(
      (c) => c.photoOf(widget.email) != null,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Foto de perfil', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'La ven tú y tus docentes. Puedes quitarla cuando quieras; sin '
              'foto se muestran tus iniciales.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              ListTile(
                leading: const ProfileIcon(Icons.photo_camera_outlined),
                title: const Text('Tomar foto'),
                onTap: () => _pick(true),
              ),
              ListTile(
                leading: const ProfileIcon(Icons.photo_library_outlined),
                title: const Text('Elegir de la galería'),
                onTap: () => _pick(false),
              ),
              if (hasPhoto)
                ListTile(
                  leading: const ProfileIcon(
                    Icons.delete_outline,
                    color: AppColors.absent,
                  ),
                  title: Text(
                    'Quitar foto',
                    style: TextStyle(color: AppColors.absent),
                  ),
                  onTap: () => _run(
                    () => context.read<PhotoCache>().remove(widget.email),
                    'Foto eliminada.',
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              MessageBanner(_error!),
            ],
          ],
        ),
      ),
    );
  }
}
