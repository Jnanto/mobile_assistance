import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_motion.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/course.dart';
import '../../../data/models/enrollment.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/report_export.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../auth/providers/auth_provider.dart';

/// D3 · Detalle del curso.
class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final Stream<Course?> _course = context
      .read<CourseRepository>()
      .watchCourse(widget.courseId);
  late final Stream<List<Enrollment>> _enrollments = context
      .read<CourseRepository>()
      .watchCourseEnrollments(widget.courseId);
  late final Stream<List<ClassSession>> _sessions = context
      .read<AttendanceRepository>()
      .watchCourseSessions(
        courseId: widget.courseId,
        teacherId: context.read<AuthProvider>().profile?.uid ?? '',
      );

  String get courseId => widget.courseId;

  @override
  void initState() {
    super.initState();
    _closeExpiredSessions();
  }

  /// Cierra (y resume) las clases que quedaron abiertas con la ventana
  /// vencida, para que cuenten en los promedios.
  Future<void> _closeExpiredSessions() async {
    final repo = context.read<AttendanceRepository>();
    final teacherId = context.read<AuthProvider>().profile?.uid ?? '';
    try {
      final sessions = await repo.getCourseSessions(
        courseId: widget.courseId,
        teacherId: teacherId,
      );
      final now = DateTime.now();
      for (final s in sessions) {
        if (s.status == SessionStatus.open && s.isFinishedAt(now)) {
          await repo.closeSession(s);
        }
      }
    } catch (_) {
      // Sin conexión: se intentará la próxima vez.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Course?>(
      stream: _course,
      builder: (context, snap) {
        final course = snap.data;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Detalle del curso'),
            actions: [
              if (course != null)
                IconButton(
                  tooltip: 'Editar curso',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push(Routes.editCourse(courseId)),
                ),
            ],
          ),
          body: switch (snap) {
            AsyncSnapshot(hasError: true) => const EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el curso',
              message: 'Revisa tu conexión e inténtalo de nuevo.',
            ),
            AsyncSnapshot(connectionState: ConnectionState.waiting) =>
              const Center(child: CircularProgressIndicator()),
            _ when course == null => const EmptyState(
              icon: Icons.search_off,
              title: 'Curso no encontrado',
              message: 'Es posible que ya no exista.',
            ),
            _ => _CourseDetailBody(
              course: course,
              enrollments: _enrollments,
              sessions: _sessions,
            ),
          },
        );
      },
    );
  }
}

class _CourseDetailBody extends StatelessWidget {
  const _CourseDetailBody({
    required this.course,
    required this.enrollments,
    required this.sessions,
  });

  final Course course;
  final Stream<List<Enrollment>> enrollments;
  final Stream<List<ClassSession>> sessions;

  Future<void> _changeStatus(
    BuildContext context,
    CourseStatus status, {
    String? confirmTitle,
    String? confirmMessage,
  }) async {
    if (confirmTitle != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmMessage ?? ''),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<CourseRepository>().setCourseStatus(course.id, status);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Enrollment>>(
      stream: enrollments,
      builder: (context, snap) => StreamBuilder<List<ClassSession>>(
        stream: sessions,
        builder: (context, sessionSnap) {
          final enrollments = snap.data ?? const <Enrollment>[];
          final active = enrollments.where((e) => e.isActive).length;
          final withdrawn = enrollments.length - active;
          final sessionList = sessionSnap.data ?? const <ClassSession>[];
          final now = DateTime.now();
          ClassSession? live;
          for (final s in sessionList) {
            if (s.isAcceptingAt(now)) live = s;
          }

          final average = averageFromSummaries(sessionList);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: staggered([
              _HeaderCard(course: course),
              const SizedBox(height: 14),
              if (course.status == CourseStatus.draft)
                ActionBarButton(
                  icon: Icons.rocket_launch_outlined,
                  label: 'Publicar curso',
                  onPressed: () => _changeStatus(
                    context,
                    CourseStatus.active,
                    confirmTitle: '¿Publicar el curso?',
                    confirmMessage:
                        'Los estudiantes inscritos podrán verlo en su app.',
                  ),
                )
              else if (live != null)
                ActionBarButton(
                  icon: Icons.sensors,
                  label: 'Ir a la clase en curso',
                  color: AppColors.present,
                  onPressed: () => context.push(Routes.liveClass(live!.id)),
                )
              else if (course.status == CourseStatus.active)
                ActionBarButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Iniciar clase en vivo',
                  onPressed: () => context.push(Routes.startClass(course.id)),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _IconStat(
                      icon: Icons.group_outlined,
                      tint: AppColors.present,
                      value: '$active',
                      label: 'Inscritos',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IconStat(
                      icon: Icons.trending_up,
                      tint: AppColors.secondary,
                      value: average == null ? '—' : percent(average),
                      valueColor: AppColors.secondary,
                      label: 'Asistencia prom.',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _IconStat(
                      icon: Icons.co_present_outlined,
                      tint: AppColors.justified,
                      value: '${sessionList.length}',
                      label: 'Clases dadas',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ShortcutCard(
                        icon: Icons.insert_chart_outlined,
                        title: 'Ver reporte',
                        subtitle: 'Estadísticas, PDF y Excel',
                        onTap: () =>
                            context.push(Routes.courseReport(course.id)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ShortcutCard(
                        icon: Icons.how_to_reg_outlined,
                        title: 'Estudiantes',
                        chip: StatusChip(
                          label: withdrawn > 0
                              ? '$active activos · $withdrawn retirados'
                              : '$active activos',
                          dot: true,
                          foreground: AppColors.present,
                          background: AppColors.presentContainer,
                        ),
                        onTap: () =>
                            context.push(Routes.courseStudents(course.id)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Icon(
                      Icons.calendar_month_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SectionTitle(
                      'Últimas sesiones',
                      count: sessionList.isEmpty
                          ? null
                          : '${sessionList.length}',
                    ),
                  ),
                ],
              ),
              if (sessionList.isEmpty)
                const Card(
                  child: EmptyState(
                    icon: Icons.event_note_outlined,
                    title: 'Aún no hay clases registradas',
                    message: 'Aquí verás el historial de asistencia por clase.',
                  ),
                )
              else
                for (final session in sessionList.take(10)) ...[
                  _SessionCard(
                    session: session,
                    live: session.isAcceptingAt(now),
                    onTap: () => context.push(Routes.liveClass(session.id)),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 16),
              if (course.status == CourseStatus.active)
                _StatusAction(
                  icon: Icons.lock_person_outlined,
                  label: 'Inhabilitar curso',
                  note:
                      'Al inhabilitar el curso no se podrán registrar nuevas '
                      'asistencias ni admitir estudiantes.',
                  color: AppColors.absent,
                  background: AppColors.absentContainer,
                  onPressed: () => _changeStatus(
                    context,
                    CourseStatus.inactive,
                    confirmTitle: '¿Inhabilitar el curso?',
                    confirmMessage:
                        'Podrás habilitarlo de nuevo cuando quieras.',
                  ),
                )
              else if (course.status == CourseStatus.inactive)
                _StatusAction(
                  icon: Icons.lock_open,
                  label: 'Habilitar curso',
                  note:
                      'El curso está inhabilitado: no admite asistencias ni '
                      'nuevos estudiantes.',
                  color: AppColors.present,
                  background: AppColors.presentContainer,
                  onPressed: () => _changeStatus(context, CourseStatus.active),
                ),
            ]),
          );
        },
      ),
    );
  }
}

/// Cabecera verde con el curso, su estado y su horario.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const mint = Color(0xFFA3F69C);
    final (statusLabel, statusColor) = switch (course.status) {
      CourseStatus.active => ('Activo', AppColors.present),
      CourseStatus.draft => ('Borrador', AppColors.textSecondary),
      CourseStatus.inactive => ('Inhabilitado', AppColors.absent),
    };
    final rooms = course.locationLabel;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E35), AppColors.primaryDark],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x260F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -12,
            top: -6,
            child: Icon(
              Icons.school_outlined,
              size: 110,
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    StatusChip(
                      label: '$statusLabel · Periodo ${course.period}',
                      dot: true,
                      foreground: statusColor,
                      background: Colors.white,
                    ),
                    StatusChip(
                      label: [
                        course.code,
                        course.group,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      foreground: Colors.white,
                      background: Colors.white.withValues(alpha: 0.14),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  course.name,
                  style: text.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                for (final meeting in course.meetings)
                  _line(context, Icons.schedule, meeting.timeLabel),
                if (rooms.isNotEmpty)
                  _line(context, Icons.meeting_room_outlined, rooms),
                _line(
                  context,
                  Icons.my_location,
                  'Radio de cobertura: ${course.radiusMeters} m',
                  color: mint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    IconData icon,
    String value, {
    Color color = Colors.white,
  }) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 18, color: color.withValues(alpha: 0.9)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: color.withValues(alpha: 0.95)),
          ),
        ),
      ],
    ),
  );
}

/// Cifra con ícono en un círculo de color.
class _IconStat extends StatelessWidget {
  const _IconStat({
    required this.icon,
    required this.tint,
    required this.value,
    required this.label,
    this.valueColor = AppColors.textPrimary,
  });

  final IconData icon;
  final Color tint;
  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: tint),
            ),
            const SizedBox(height: 6),
            Text(value, style: text.headlineSmall?.copyWith(color: valueColor)),
            Text(
              label,
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Acceso rápido (reporte, estudiantes) en una tarjeta.
class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.chip,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? chip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(
                icon: icon,
                color: AppColors.textSecondary,
                background: AppColors.surfaceVariant,
                size: 40,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ?chip,
            ],
          ),
        ),
      ),
    );
  }
}

/// Una clase en la lista de "Últimas sesiones".
class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.live,
    required this.onTap,
  });

  final ClassSession session;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final start = session.startedAt;
    final summary = session.summary;
    final attended = summary == null ? null : summary.expected - summary.absent;
    final rate = summary == null || summary.expected == 0
        ? null
        : attended! / summary.expected;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.presentContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${start.day}',
                      style: text.titleMedium?.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    Text(
                      ScheduleFormat.monthShort(start).toUpperCase(),
                      style: text.labelSmall?.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Clase #${session.number}',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${ScheduleFormat.weekday(start)} · '
                      '${ScheduleFormat.clock(start)}'
                      '${session.room.isEmpty ? '' : ' · ${session.room}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (live)
                const StatusChip(
                  label: 'En curso',
                  dot: true,
                  foreground: AppColors.present,
                  background: AppColors.presentContainer,
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (rate != null)
                      StatusChip(
                        label: percent(rate),
                        icon: Icons.check_circle_outline,
                        foreground: AppColors.present,
                        background: AppColors.presentContainer,
                      ),
                    if (summary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '$attended / ${summary.expected}',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ] else
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textMuted,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón ancho para inhabilitar o habilitar el curso, con su explicación.
class _StatusAction extends StatelessWidget {
  const _StatusAction({
    required this.icon,
    required this.label,
    required this.note,
    required this.color,
    required this.background,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final String note;
  final Color color;
  final Color background;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: color,
            elevation: 0,
          ),
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          textAlign: TextAlign.center,
          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
