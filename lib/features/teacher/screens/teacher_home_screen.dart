import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/course.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/report_export.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../profile/profile_controllers.dart';
import '../../profile/profile_tab.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_courses_provider.dart';
import '../widgets/teacher_course_card.dart';
import '../widgets/teacher_profile_section.dart';

/// Inicio del docente: pestañas Cursos (D1) y Perfil.
class TeacherHomeScreen extends StatefulWidget {
  const TeacherHomeScreen({super.key});

  @override
  State<TeacherHomeScreen> createState() => _TeacherHomeScreenState();
}

class _TeacherHomeScreenState extends State<TeacherHomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final teacherId = context.select<AuthProvider, String>(
      (a) => a.profile?.uid ?? '',
    );
    return ChangeNotifierProvider(
      create: (context) {
        final provider = TeacherCoursesProvider(
          context.read<CourseRepository>(),
          context.read<AttendanceRepository>(),
          teacherId,
        );
        // Los avisos de clase siguen a los cursos del docente.
        final reminders = context.read<RemindersController>();
        provider.addListener(() => reminders.sync(provider.courses));
        return provider;
      },
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            leadingWidth: 56,
            leading: const BrandMark(),
            title: Text(_tab == 0 ? 'Cursos' : 'Perfil'),
            actions: [
              ProfileBadgeButton(onPressed: () => setState(() => _tab = 1)),
            ],
          ),
          body: FadeIndexedStack(
            index: _tab,
            children: const [
              _CoursesTab(),
              ProfileTab(
                heroFooter: TeacherHeroStats(),
                roleSections: [TeacherProfileSection()],
              ),
            ],
          ),
          floatingActionButton: _tab == 0
              ? FloatingActionButton.extended(
                  onPressed: () async {
                    final provider = context.read<TeacherCoursesProvider>();
                    await context.push(Routes.newCourse);
                    provider.refreshCounts();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo curso'),
                )
              : null,
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
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// D1 · Mis cursos (docente).
class _CoursesTab extends StatelessWidget {
  const _CoursesTab();

  Future<void> _openCourse(BuildContext context, Course course) async {
    final provider = context.read<TeacherCoursesProvider>();
    await context.push(Routes.courseDetail(course.id));
    provider.refreshCounts();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TeacherCoursesProvider>();
    final firstName = context.select<AuthProvider, String>(
      (a) => a.profile?.firstName ?? '',
    );
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();

    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final next = provider.nextClassToday(now);
    final courses = provider.courses;

    final profile = context
        .select<AuthProvider, ({String name, String dep, String email})>(
          (a) => (
            name: a.profile?.name ?? '',
            dep: a.profile?.department ?? '',
            email: a.profile?.email ?? '',
          ),
        );

    return RefreshIndicator(
      onRefresh: provider.refreshCounts,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: staggered([
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '¡Hola, $firstName!',
                            style: text.headlineSmall,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.secondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        'Periodo ${ScheduleFormat.recentPeriods(now).first}',
                        if (profile.dep.isNotEmpty) profile.dep,
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              PersonAvatar(name: profile.name, email: profile.email),
            ],
          ),
          const SizedBox(height: 16),
          if (provider.error != null) ...[
            MessageBanner(provider.error!),
            const SizedBox(height: 16),
          ],
          if (next != null) ...[
            _NextClassCard(
              course: next,
              enrolled: provider.enrolledCount(next.id),
              now: now,
              onOpen: () => _openCourse(context, next),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${provider.classesToday(now).length}',
                  label: 'Clases hoy',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: switch (provider.globalAverage) {
                    null => '—',
                    final avg => percent(avg),
                  },
                  label: 'Asist. global',
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatTile(
                  value: '${provider.totalStudents}',
                  label: 'Estudiantes',
                  color: AppColors.tertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SectionTitle(
            'Tus asignaturas',
            count:
                '${courses.length} ${courses.length == 1 ? 'curso' : 'cursos'}',
          ),
          if (courses.isEmpty)
            const EmptyState(
              icon: Icons.class_outlined,
              title: 'Aún no tienes cursos',
              message: 'Crea tu primer curso con el botón "Nuevo curso".',
            ),
          for (final course in courses) ...[
            TeacherCourseCard(
              course: course,
              enrolled: provider.enrolledCount(course.id),
              average: provider.courseAverage(course.id),
              now: now,
              onTap: () => _openCourse(context, course),
            ),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    );
  }
}

/// Tarjeta destacada con la clase en curso o la próxima de hoy.
class _NextClassCard extends StatelessWidget {
  const _NextClassCard({
    required this.course,
    required this.enrolled,
    required this.now,
    required this.onOpen,
  });

  final Course course;
  final int enrolled;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final meeting = course.currentOrNextToday(now);
    final ongoing = meeting?.isOngoing(now) ?? false;
    final location = meeting?.locationLabel ?? course.locationLabel;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            AppColors.surface,
            AppColors.primaryContainer.withValues(alpha: 0.35),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 6,
            spreadRadius: -1,
            offset: Offset(0, 4),
          ),
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 4,
            spreadRadius: -2,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: StatusChip(
                    label: ongoing
                        ? 'EN HORARIO · CLASE AHORA'
                        : 'PRÓXIMA · CLASE HOY',
                    dot: true,
                    foreground: ongoing
                        ? AppColors.tertiary
                        : AppColors.present,
                    background: ongoing
                        ? AppColors.lateContainer
                        : AppColors.presentContainer,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.schedule,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Inicia '
                        '${ScheduleFormat.time(meeting?.startMinutes ?? 0)}',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(course.name, style: text.headlineSmall),
            Text(
              course.group,
              style: text.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            InsetPanel(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: _MetaTile(
                      icon: Icons.calendar_today,
                      label: 'Horario',
                      value: meeting?.timeLabel ?? course.scheduleLabel,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetaTile(
                      icon: Icons.meeting_room_outlined,
                      label: 'Ubicación',
                      value: location.isEmpty ? 'Sin salón' : location,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.groups, size: 18, color: AppColors.secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$enrolled estudiantes inscritos',
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Text(
                  ongoing ? 'Listo para registro' : 'Más tarde hoy',
                  style: text.labelMedium?.copyWith(color: AppColors.secondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerLow,
                      foregroundColor: AppColors.textPrimary,
                      iconColor: AppColors.primary,
                      textStyle: text.labelLarge,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onOpen,
                    icon: const Icon(Icons.info_outline, size: 20),
                    label: const Text('Ver detalle'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryDark,
                      textStyle: text.labelLarge,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => context.push(Routes.startClass(course.id)),
                    icon: const Icon(Icons.play_circle_outline, size: 20),
                    label: const Text('Iniciar clase'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dato del horario o la ubicación dentro de la tarjeta destacada.
class _MetaTile extends StatelessWidget {
  const _MetaTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Color(0x0D0F172A), blurRadius: 2),
            ],
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: text.labelSmall?.copyWith(color: AppColors.textMuted),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
