import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/report_export.dart';
import '../../../data/services/report_loader.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/report_charts.dart';

/// D6 · Reporte de asistencia del curso.
class CourseReportScreen extends StatefulWidget {
  const CourseReportScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseReportScreen> createState() => _CourseReportScreenState();
}

class _CourseReportScreenState extends State<CourseReportScreen> {
  late Future<CourseReportData> _data = _load();
  bool _exporting = false;

  Future<CourseReportData> _load() => loadCourseReport(
    courses: context.read<CourseRepository>(),
    attendance: context.read<AttendanceRepository>(),
    courseId: widget.courseId,
  );

  Future<void> _reload() async {
    setState(() {
      _data = _load();
    });
    await _data;
  }

  Future<void> _export(CourseReportData data, {required bool pdf}) async {
    final sharer = context.read<FileSharer>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final now = DateTime.now();
      if (pdf) {
        final bytes = await buildCourseReportPdf(
          course: data.course,
          report: data.report,
          generatedAt: now,
        );
        await sharer.share(
          bytes,
          courseReportFileName(data.course, now, 'pdf'),
          pdfMime,
        );
      } else {
        final bytes = buildCourseReportXlsx(
          course: data.course,
          report: data.report,
        );
        await sharer.share(
          bytes,
          courseReportFileName(data.course, now, 'xlsx'),
          xlsxMime,
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo exportar: ${AuthService.messageFor(e)}'),
        ),
      );
    }
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reporte de asistencia')),
      body: FutureBuilder<CourseReportData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar el reporte',
              message: AuthService.messageFor(snap.error!),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return RefreshIndicator(onRefresh: _reload, child: _body(snap.data!));
        },
      ),
    );
  }

  Widget _body(CourseReportData data) {
    final text = Theme.of(context).textTheme;
    final report = data.report;
    final course = data.course;
    final average = report.average;

    const minRate = 1 - AppConfig.maxAbsenceRate;
    final students = [...report.students]
      ..sort((a, b) => b.stats.absenceRate.compareTo(a.stats.absenceRate));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Row(
          children: [
            const Icon(
              Icons.school_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'REPORTE DEL CURSO',
              style: text.labelSmall?.copyWith(
                color: AppColors.primary,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        Text('Reporte de asistencia', style: text.headlineSmall),
        Text(
          '${course.name} · ${course.group} · Periodo ${course.period}',
          style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 14),
        if (report.sessions.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.bar_chart,
              title: 'Aún no hay clases terminadas',
              message:
                  'El reporte se arma con las clases cerradas o cuya ventana '
                  'de asistencia ya terminó.',
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PROMEDIO GENERAL',
                        style: text.labelSmall?.copyWith(
                          color: Colors.white70,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        average == null ? '—' : percent(average),
                        style: text.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${report.sessions.length} clases · '
                        '${report.students.length} estudiantes · '
                        '${report.atRisk.length} en riesgo',
                        style: text.labelSmall?.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      if (average != null)
                        Row(
                          children: [
                            Icon(
                              average >= minRate
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              size: 16,
                              color: const Color(0xFFA3F69C),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                average >= minRate
                                    ? 'Sobre el mínimo del '
                                          '${(minRate * 100).round()} %'
                                    : 'Bajo el mínimo del '
                                          '${(minRate * 100).round()} %',
                                style: text.labelSmall?.copyWith(
                                  color: const Color(0xFFA3F69C),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Evolución por clase',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const StatusChip(
                        label: '% de asistencia',
                        dot: true,
                        foreground: AppColors.present,
                        background: AppColors.presentContainer,
                      ),
                    ],
                  ),
                  Text(
                    'Desempeño clase a clase '
                    '(1–${report.sessions.length})',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AttendanceBarChart(
                    bars: [
                      for (final r in report.sessionRates)
                        RateBar(
                          label: 'C${r.session.number}',
                          rate: r.rate,
                          detail:
                              'Clase #${r.session.number} · '
                              '${ScheduleFormat.shortDate(r.session.startedAt)}'
                              ': ${percent(r.rate)} '
                              '(${r.expected - r.absent} de ${r.expected})',
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Distribución de estados',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        'Total: ${report.total} registros',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  StatusDonut(
                    centerValue: average == null ? '—' : percent(average),
                    centerLabel: 'Asistencia',
                    counts: [
                      StatusCount(AttendanceStatus.present, report.present),
                      StatusCount(AttendanceStatus.review, report.review),
                      StatusCount(AttendanceStatus.late, report.late),
                      StatusCount(AttendanceStatus.justified, report.justified),
                      StatusCount(AttendanceStatus.absent, report.absent),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estudiantes y riesgo de inasistencia',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Límite máximo de inasistencia: '
                      '${percent(AppConfig.maxAbsenceRate)}',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (report.atRisk.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: AppColors.absentContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: AppColors.absent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final row in students) ...[
            _StudentRow(
              row: row,
              onTap: () async {
                await context.push(
                  Routes.studentFile(course.id, row.enrollment.email),
                );
                if (mounted) _reload();
              },
            ),
            const SizedBox(height: 8),
          ],
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  shape: const StadiumBorder(),
                ),
                onPressed: _exporting || report.sessions.isEmpty
                    ? null
                    : () => _export(data, pdf: true),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Exportar PDF'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                onPressed: _exporting || report.sessions.isEmpty
                    ? null
                    : () => _export(data, pdf: false),
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Excel'),
              ),
            ),
          ],
        ),
        if (_exporting) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
        const SizedBox(height: 8),
        const FieldHint(
          'Las llegadas tarde y los justificados no cuentan como '
          'inasistencia. "Por revisar" cuenta como asistencia hasta que lo '
          'rechaces.',
          icon: Icons.info_outline,
        ),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.row, required this.onTap});

  final StudentReportRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stats = row.stats;
    final color = switch (stats.risk) {
      RiskLevel.ok => AppColors.present,
      RiskLevel.warning => AppColors.late,
      RiskLevel.exceeded => AppColors.absent,
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  PersonAvatar(
                    name: row.enrollment.name,
                    email: row.enrollment.email,
                    size: 40,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.enrollment.name,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Cód. ${row.enrollment.studentCode} · '
                          '${stats.absent} '
                          '${stats.absent == 1 ? 'falta' : 'faltas'} de '
                          '${stats.total}',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        percent(stats.attendanceRate),
                        style: text.titleMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      RiskChip(level: stats.risk, compact: true),
                    ],
                  ),
                ],
              ),
              if (stats.risk != RiskLevel.ok) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: stats.risk == RiskLevel.exceeded
                        ? AppColors.absentContainer
                        : AppColors.lateContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        stats.risk == RiskLevel.exceeded
                            ? Icons.error_outline
                            : Icons.priority_high,
                        size: 16,
                        color: color,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          stats.risk == RiskLevel.exceeded
                              ? 'Supera el límite de inasistencia'
                              : 'Cerca del límite de inasistencia',
                          style: text.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Text(
                        '${percent(stats.absenceRate)} fallas',
                        style: text.labelSmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
