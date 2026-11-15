import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/enrollment.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../auth/providers/auth_provider.dart';

/// Abre la hoja para asignar un estado a mano. Devuelve `true` si se guardó.
Future<bool> showManualStatusSheet(
  BuildContext context, {
  required ClassSession session,
  required Enrollment enrollment,
  AttendanceStatus? current,
  AttendanceStatus? initial,
  String? suggestedReason,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ManualStatusSheet(
      session: session,
      enrollment: enrollment,
      current: current,
      initial: initial,
      suggestedReason: suggestedReason,
    ),
  );
  return saved == true;
}

/// D7 · Corrección manual (también se usa en D5 para marcar sin QR).
class ManualStatusSheet extends StatefulWidget {
  const ManualStatusSheet({
    super.key,
    required this.session,
    required this.enrollment,
    this.current,
    this.initial,
    this.suggestedReason,
  });

  final ClassSession session;
  final Enrollment enrollment;
  final AttendanceStatus? current;
  final AttendanceStatus? initial;
  final String? suggestedReason;

  @override
  State<ManualStatusSheet> createState() => _ManualStatusSheetState();
}

class _ManualStatusSheetState extends State<ManualStatusSheet> {
  late final _reason = TextEditingController(text: widget.suggestedReason);
  late AttendanceStatus? _status = widget.initial;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_status == null) {
      setState(() => _error = 'Elige el nuevo estado.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el motivo del cambio.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AttendanceRepository>().setManualStatus(
        session: widget.session,
        enrollment: widget.enrollment,
        status: _status!,
        reason: _reason.text,
        teacherId: context.read<AuthProvider>().profile!.uid,
      );
      if (mounted) Navigator.pop(context, true);
      return;
    } catch (e) {
      _error = AuthService.messageFor(e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final teacherName = context.select<AuthProvider, String>(
      (a) => a.profile?.name ?? '',
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Flexible(
                    child: StatusChip(
                      label: 'Corrección manual',
                      foreground: AppColors.present,
                      background: AppColors.presentContainer,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '· Docente',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('Modificar estado de asistencia', style: text.headlineSmall),
              Text(
                'Clase #${widget.session.number} · '
                '${ScheduleFormat.date(widget.session.startedAt)} · '
                '${ScheduleFormat.clock(widget.session.startedAt)}',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              InsetPanel(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    PersonAvatar(
                      name: widget.enrollment.name,
                      email: widget.enrollment.email,
                      size: 38,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.enrollment.name,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.current != null)
                            Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'Estado actual: '),
                                  TextSpan(
                                    text: attendanceStyle(widget.current!)
                                        .label,
                                    style: TextStyle(
                                      color: attendanceStyle(widget.current!)
                                          .fg,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              style: text.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Nuevo estado de asistencia'),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 3.4,
                children: [
                  for (final status in manualStatusValues.keys)
                    _StatusOption(
                      status: status,
                      selected: _status == status,
                      onTap: () => setState(() => _status = status),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const FieldLabel(
                'Motivo del cambio',
                trailing: 'Máx. 300 caracteres',
              ),
              TextField(
                controller: _reason,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ej. Incapacidad médica presentada en Bienestar',
                ),
              ),
              NoticeBox(
                icon: Icons.verified_user_outlined,
                color: AppColors.textSecondary,
                background: AppColors.surfaceVariant,
                child: Text(
                  'El cambio queda registrado con tu nombre ($teacherName) y '
                  'la hora del servidor de SelvaCheck.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                MessageBanner(_error!),
              ],
              const SizedBox(height: 16),
              LoadingButton(
                label: 'Guardar cambio',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _save,
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opción de estado con su color, ícono y marca de selección.
class _StatusOption extends StatelessWidget {
  const _StatusOption({
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final AttendanceStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = attendanceStyle(status);
    return Material(
      color: selected ? style.bg : AppColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? style.fg : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(style.icon, size: 20, color: style.fg),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  style.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? style.fg : AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle,
                size: 18,
                color: selected ? style.fg : AppColors.surfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
