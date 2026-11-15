import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/course.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/report_export.dart';
import '../../../data/services/report_loader.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../../shared/widgets/student_stats_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/student_courses_provider.dart';

/// E5 · Mi asistencia.
class MyAttendanceTab extends StatefulWidget {
  const MyAttendanceTab({super.key});

  @override
  State<MyAttendanceTab> createState() => _MyAttendanceTabState();
}

class _MyAttendanceTabState extends State<MyAttendanceTab> {
  String? _courseId;
  final Map<String, Future<StudentFileData>> _cache = {};
  bool _exporting = false;

  Future<StudentFileData> _load(String courseId, {bool force = false}) {
    if (force) _cache.remove(courseId);
    return _cache.putIfAbsent(
      courseId,
      () => loadStudentFile(
        courses: context.read<CourseRepository>(),
        attendance: context.read<AttendanceRepository>(),
        courseId: courseId,
        email: context.read<AuthProvider>().profile?.email ?? '',
        asTeacher: false,
      ),
    );
  }

  Future<void> _downloadCertificate(StudentFileData data) async {
    final profile = context.read<AuthProvider>().profile!;
    final sharer = context.read<FileSharer>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      final bytes = await buildAttendanceCertificatePdf(
        studentName: data.enrollment.name,
        studentCode: data.enrollment.studentCode,
        email: profile.email,
        course: data.course,
        stats: data.stats,
        generatedAt: now,
      );
      await sharer.share(
        bytes,
        'constancia_${courseReportFileName(data.course, now, 'pdf')}',
        pdfMime,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo generar: ${AuthService.messageFor(e)}'),
        ),
      );
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StudentCoursesProvider>();
    final courses = provider.courses;
    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (courses.isEmpty) {
      return const EmptyState(
        icon: Icons.bar_chart,
        title: 'Aún no estás en ningún curso',
        message: 'Cuando un docente te inscriba, verás aquí tu asistencia.',
      );
    }
    final selectedId = courses.any((c) => c.id == _courseId)
        ? _courseId!
        : courses.first.id;

    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _load(selectedId, force: true);
        });
        await _cache[selectedId];
        await provider.refreshStats();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'ASIGNATURA ACTIVA',
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: AppColors.textMuted, letterSpacing: 1),
                ),
              ),
              const Icon(Icons.swap_horiz, size: 16, color: AppColors.primary),
              const SizedBox(width: 4),
              Text(
                '${courses.length} '
                '${courses.length == 1 ? 'inscrita' : 'inscritas'}',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final course in courses) ...[
                  _CourseOption(
                    course: course,
                    selected: course.id == selectedId,
                    onTap: () => setState(() => _courseId = course.id),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<StudentFileData>(
            key: ValueKey(selectedId),
            future: _load(selectedId),
            builder: (context, snap) {
              if (snap.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudo cargar tu asistencia',
                  message: AuthService.messageFor(snap.error!),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return _content(snap.data!);
            },
          ),
        ],
      ),
    );
  }

  Widget _content(StudentFileData data) {
    final stats = data.stats;
    final text = Theme.of(context).textTheme;
    final limit = percent(AppConfig.maxAbsenceRate);
    final (
      String title,
      String message,
      Color fg,
      Color bg,
      IconData icon,
    ) = switch (stats.risk) {
      RiskLevel.exceeded => (
        'Superaste el límite',
        'Superaste el límite de inasistencia ($limit). Habla con tu '
            'docente.',
        AppColors.absent,
        AppColors.absentContainer,
        Icons.report,
      ),
      RiskLevel.warning => (
        'Advertencia de asistencia',
        'Te estás acercando al límite de inasistencia ($limit).',
        AppColors.late,
        AppColors.lateContainer,
        Icons.warning_rounded,
      ),
      RiskLevel.ok => (
        'Vas bien',
        'Estás al día con el límite de inasistencia ($limit).',
        AppColors.present,
        AppColors.presentContainer,
        Icons.verified,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StudentStatsHeader(
          name: data.course.name,
          subtitle: '${data.course.group} · Prof. ${data.course.teacherName}',
          title: 'Métricas del periodo ${data.course.period}',
          stats: stats,
        ),
        const SizedBox(height: 12),
        if (stats.total > 0)
          NoticeBox(
            title: title,
            icon: icon,
            color: fg,
            background: bg,
            child: Text(message),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Icon(
                Icons.history,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SectionTitle(
                'Historial de clases',
                trailing:
                    '${stats.total} ${stats.total == 1 ? 'registro' : 'registros'}',
              ),
            ),
          ],
        ),
        if (stats.history.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.event_note_outlined,
              title: 'Sin clases todavía',
              message: 'Aquí aparecerán tus clases cuando terminen.',
            ),
          ),
        for (final entry in stats.history) ...[
          HistoryTile(entry: entry),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
          onPressed: _exporting || stats.total == 0
              ? null
              : () => _downloadCertificate(data),
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Descargar constancia (PDF)'),
        ),
        const SizedBox(height: 8),
        Text(
          'La constancia la genera SelvaCheck con tus registros; no es un '
          'certificado oficial de la universidad.',
          textAlign: TextAlign.center,
          style: text.labelSmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

/// Tarjeta para elegir la asignatura; la elegida va en verde oscuro.
class _CourseOption extends StatelessWidget {
  const _CourseOption({
    required this.course,
    required this.selected,
    required this.onTap,
  });

  final Course course;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fg = selected ? Colors.white : AppColors.textPrimary;
    return Material(
      color: selected ? AppColors.primaryDark : AppColors.surface,
      elevation: selected ? 2 : 1,
      shadowColor: AppColors.shadow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.15)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.class_outlined,
                  size: 18,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      [
                        course.group,
                        course.locationLabel,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: Colors.white,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
