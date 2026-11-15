import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/course.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';
import '../../../data/services/report_export.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../profile/profile_controllers.dart';
import '../../profile/profile_tab.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_courses_provider.dart';
import 'my_attendance_tab.dart';

/// Inicio del estudiante: Cursos (E1), Mi asistencia y Perfil.
class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  int _tab = 0;

  /// Refresca las cuentas regresivas de las clases en vivo.
  Timer? _ticker;

  static const _titles = ['Mis cursos', 'Mi asistencia', 'Perfil'];

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tab == 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = context.select<AuthProvider, String>(
      (a) => a.profile?.email ?? '',
    );
    return ChangeNotifierProvider(
      create: (context) {
        final provider = StudentCoursesProvider(
          context.read<CourseRepository>(),
          context.read<AttendanceRepository>(),
          email,
        );
        // Los avisos de clase siguen a los cursos del estudiante.
        final reminders = context.read<RemindersController>();
        provider.addListener(() => reminders.sync(provider.courses));
        return provider;
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 16,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SELVA CHECK',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.textMuted, letterSpacing: 1),
              ),
              Text(_titles[_tab]),
            ],
          ),
          actions: [
            ProfileBadgeButton(onPressed: () => setState(() => _tab = 2)),
          ],
        ),
        body: FadeIndexedStack(
          index: _tab,
          children: [
            _CoursesTab(now: DateTime.now()),
            const MyAttendanceTab(),
            const ProfileTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.school_outlined),
              selectedIcon: Icon(Icons.school),
              label: 'Cursos',
            ),
            NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart),
              label: 'Mi asistencia',
            ),
            NavigationDestination(
              icon: Icon(Icons.account_circle_outlined),
              selectedIcon: Icon(Icons.account_circle),
              label: 'Perfil',
            ),
          ],
        ),
      ),
    );
  }
}

/// E1 · Mis cursos (estudiante).
class _CoursesTab extends StatelessWidget {
  const _CoursesTab({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCoursesProvider>();
    final firstName = context.select<AuthProvider, String>(
      (a) => a.profile?.firstName ?? '',
    );
    final text = Theme.of(context).textTheme;

    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final courses = provider.courses;

    final profile = context
        .select<AuthProvider, ({String name, String program, String email})>(
          (a) => (
            name: a.profile?.name ?? '',
            program: a.profile?.program ?? '',
            email: a.profile?.email ?? '',
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: staggered([
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                PersonAvatar(
                  name: profile.name,
                  email: profile.email,
                  size: 52,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('¡Hola, $firstName!', style: text.headlineSmall),
                      Text(
                        profile.program.isEmpty
                            ? 'Periodo ${ScheduleFormat.recentPeriods(now).first}'
                            : profile.program,
                        style: text.bodySmall?.copyWith(
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
        const SizedBox(height: 16),
        if (provider.error != null) ...[
          MessageBanner(provider.error!),
          const SizedBox(height: 16),
        ],
        for (final session in provider.liveSessions(now)) ...[
          _LiveClassCard(key: ValueKey(session.id), session: session, now: now),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 4),
        SectionTitle(
          'Mis asignaturas inscritas',
          count: '${courses.length}',
          trailing: 'Semestre ${ScheduleFormat.recentPeriods(now).first}',
        ),
        if (courses.isEmpty)
          const EmptyState(
            icon: Icons.class_outlined,
            title: 'Aún no estás en ningún curso',
            message:
                'Cuando un docente te agregue a un curso publicado, '
                'aparecerá aquí.',
          ),
        for (final course in courses) ...[
          _StudentCourseCard(course: course, now: now),
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}

class _StudentCourseCard extends StatelessWidget {
  const _StudentCourseCard({required this.course, required this.now});

  final Course course;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final inactive = course.status == CourseStatus.inactive;
    final stats = context.watch<StudentCoursesProvider>().statsFor(course.id);
    final hasData = stats != null && stats.total > 0;
    final rateColor = !hasData
        ? AppColors.textMuted
        : switch (stats.risk) {
            RiskLevel.ok => AppColors.present,
            RiskLevel.warning => AppColors.late,
            RiskLevel.exceeded => AppColors.absent,
          };
    final place = [
      course.locationLabel,
      if (course.teacherName.isNotEmpty) 'Prof. ${course.teacherName}',
    ].where((s) => s.isNotEmpty).join(' · ');
    return Opacity(
      opacity: inactive ? 0.6 : 1,
      child: StripeCard(
        color: inactive
            ? AppColors.outlineVariant
            : AppColors.courseColor(course.colorIndex),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CourseAvatar(course: course),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      Text(
                        [
                          course.group,
                          course.scheduleLabel,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                CourseTodayChip(course: course, now: now),
              ],
            ),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 8),
              InfoRow(icon: Icons.pin_drop_outlined, text: place),
            ],
            const SizedBox(height: 10),
            InsetPanel(
              child: Row(
                children: [
                  Icon(Icons.insights, size: 18, color: rateColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Asistencia individual',
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!hasData)
                    Text(
                      'Sin clases aún',
                      style: text.labelMedium?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    )
                  else ...[
                    Text(
                      percent(stats.attendanceRate),
                      style: text.titleSmall?.copyWith(
                        color: rateColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '(${stats.total - stats.absent}/${stats.total})',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de una clase con la ventana de asistencia abierta.
class _LiveClassCard extends StatefulWidget {
  const _LiveClassCard({super.key, required this.session, required this.now});

  final ClassSession session;
  final DateTime now;

  @override
  State<_LiveClassCard> createState() => _LiveClassCardState();
}

class _LiveClassCardState extends State<_LiveClassCard> {
  // Se crea una sola vez: la tarjeta se redibuja cada segundo.
  late final Stream<AttendanceRecord?> _record = context
      .read<AttendanceRepository>()
      .watchMyRecord(
        widget.session.id,
        context.read<AuthProvider>().profile?.email ?? '',
      );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final session = widget.session;
    final now = widget.now;
    final presentLeft = session.presentDeadline.difference(now).inSeconds;
    final closeLeft = session.closesAt.difference(now).inSeconds;
    final countdown = presentLeft > 0
        ? 'Te quedan ${Formatters.mmss(presentLeft)} para marcar Presente'
        : 'Te quedan ${Formatters.mmss(closeLeft)} para marcar Tarde';
    const onCard = Colors.white;

    return StreamBuilder<AttendanceRecord?>(
      stream: _record,
      builder: (context, snap) {
        final record = snap.data;
        final seconds = presentLeft > 0 ? presentLeft : closeLeft;
        const mint = Color(0xFFA3F69C); // secondary-fixed
        final mono = text.labelLarge?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Container(
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
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: mint,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'EN VIVO · VENTANA ABIERTA',
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: onCard,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 15, color: mint),
                        const SizedBox(width: 4),
                        Text(
                          Formatters.mmss(seconds),
                          style: mono?.copyWith(color: onCard, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Registro de asistencia en curso',
                style: text.labelMedium?.copyWith(color: mint),
              ),
              const SizedBox(height: 2),
              Text(
                session.courseName,
                style: text.headlineSmall?.copyWith(color: onCard),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.meeting_room_outlined,
                    size: 18,
                    color: mint,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        session.room,
                        if (session.teacherName.isNotEmpty)
                          'Prof. ${session.teacherName}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: text.bodyMedium?.copyWith(
                        color: onCard.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 20, color: mint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        countdown,
                        style: text.labelMedium?.copyWith(color: onCard),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (record == null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFA0F399),
                    foregroundColor: const Color(0xFF217128),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () =>
                      context.push(Routes.markAttendance(session.id)),
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Marcar presente'),
                )
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: onCard,
                    side: const BorderSide(color: onCard),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () =>
                      context.push(Routes.attendanceResult(session.id)),
                  icon: const Icon(Icons.verified_outlined),
                  label: Text(
                    'Registrada · '
                    '${attendanceStyle(record.statusFor(session)).label}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
