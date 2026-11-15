import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/validators.dart';
import '../../../data/models/course.dart';
import '../../../data/models/enrollment.dart';
import '../../../data/models/roster_entry.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/report_export.dart';
import '../../../data/services/report_loader.dart';
import '../../../data/services/roster_parser.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/report_charts.dart';
import '../../auth/providers/auth_provider.dart';

enum _Filter { all, active, withdrawn }

/// D8 · Estudiantes inscritos en un curso.
class CourseStudentsScreen extends StatefulWidget {
  const CourseStudentsScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<CourseStudentsScreen> createState() => _CourseStudentsScreenState();
}

class _CourseStudentsScreenState extends State<CourseStudentsScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  late final Stream<Course?> _courseStream;
  late final Stream<List<Enrollment>> _enrollmentStream;

  /// Asistencia de cada estudiante (lee todos los registros del curso).
  Future<CourseReportData>? _report;

  @override
  void initState() {
    super.initState();
    final repo = context.read<CourseRepository>();
    _courseStream = repo.watchCourse(widget.courseId);
    _enrollmentStream = repo.watchCourseEnrollments(widget.courseId);
    _report = _fetchReport();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<CourseReportData> _fetchReport() {
    final report = loadCourseReport(
      courses: context.read<CourseRepository>(),
      attendance: context.read<AttendanceRepository>(),
      courseId: widget.courseId,
    );
    // Si falla, cada estudiante se muestra sin porcentaje.
    report.ignore();
    return report;
  }

  void _loadReport() => setState(() {
    _report = _fetchReport();
  });

  Future<void> _openFile(Enrollment enrollment) async {
    await context.push(Routes.studentFile(widget.courseId, enrollment.email));
    if (mounted) _loadReport();
  }

  Future<void> _editGrade(Enrollment enrollment) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _GradeDialog(enrollment: enrollment),
    );
    if (result == null || !mounted) return;
    final raw = result.trim().replaceAll(',', '.');
    final grade = raw.isEmpty ? null : double.tryParse(raw);
    if (raw.isNotEmpty && (grade == null || grade < 0 || grade > 5)) {
      _toast('La nota debe estar entre 0.0 y 5.0.');
      return;
    }
    try {
      await context.read<CourseRepository>().setGrade(
        courseId: widget.courseId,
        email: enrollment.email,
        grade: grade == null ? null : (grade * 10).round() / 10,
      );
    } catch (e) {
      if (mounted) _toast(AuthService.messageFor(e));
    }
  }

  Future<void> _addStudent() async {
    final added = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddStudentSheet(courseId: widget.courseId),
    );
    if (added != null && mounted) _toast(added);
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xls', 'xlsx', 'csv'],
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    final result = RosterParser.fromFile(file.name, bytes);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ImportDialog(
        courseId: widget.courseId,
        fileName: file.name,
        result: result,
      ),
    );
  }

  void _showFormatHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Formato del archivo'),
        content: const SelectableText(RosterParser.formatHelp),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw(Enrollment enrollment, StudentStats? stats) async {
    final done = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _WithdrawSheet(enrollment: enrollment, stats: stats),
    );
    if (done == true && mounted) {
      _toast('${enrollment.name} fue dado de baja del curso.');
    }
  }

  Future<void> _reactivate(Enrollment enrollment) async {
    final teacherId = context.read<AuthProvider>().profile!.uid;
    try {
      await context.read<CourseRepository>().enrollStudent(
        courseId: widget.courseId,
        teacherId: teacherId,
        student: RosterEntry(
          email: enrollment.email,
          name: enrollment.name,
          studentCode: enrollment.studentCode,
        ),
      );
      if (mounted) _toast('${enrollment.name} volvió a estar activo.');
    } catch (e) {
      if (mounted) _toast(AuthService.messageFor(e));
    }
  }

  List<Enrollment> _visible(List<Enrollment> all) {
    final query = _search.text.trim().toLowerCase();
    final filtered = all.where((e) {
      final matchesFilter = switch (_filter) {
        _Filter.all => true,
        _Filter.active => e.isActive,
        _Filter.withdrawn => !e.isActive,
      };
      final matchesQuery =
          query.isEmpty ||
          e.name.toLowerCase().contains(query) ||
          e.studentCode.contains(query) ||
          e.email.contains(query);
      return matchesFilter && matchesQuery;
    }).toList();
    filtered.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<Course?>(
      stream: _courseStream,
      builder: (context, courseSnap) {
        final course = courseSnap.data;
        final acceptsStudents =
            course != null && course.status != CourseStatus.inactive;
        return Scaffold(
          appBar: AppBar(
            title: Column(
              children: [
                const Text('Estudiantes inscritos'),
                if (course != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: StatusChip(
                      label: course.name,
                      dot: true,
                      foreground: AppColors.present,
                      background: AppColors.presentContainer,
                    ),
                  ),
              ],
            ),
          ),
          body: StreamBuilder<List<Enrollment>>(
            stream: _enrollmentStream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const EmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudo cargar la lista',
                  message: 'Revisa tu conexión e inténtalo de nuevo.',
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data!;
              final activeCount = all.where((e) => e.isActive).length;
              final visible = _visible(all);

              final withdrawnCount = all.length - activeCount;

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  FutureBuilder<CourseReportData>(
                    future: _report,
                    builder: (context, reportSnap) => _SummaryCard(
                      course: course,
                      active: activeCount,
                      withdrawn: withdrawnCount,
                      atRisk: reportSnap.data?.report.atRisk.length,
                      onAdd: acceptsStudents ? _addStudent : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!acceptsStudents && course != null) ...[
                    const MessageBanner(
                      'El curso está inhabilitado: no se pueden agregar ni '
                      'reactivar estudiantes.',
                      kind: BannerKind.info,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Material(
                    color: AppColors.surface,
                    elevation: 1,
                    shadowColor: AppColors.shadow,
                    borderRadius: BorderRadius.circular(16),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        fillColor: AppColors.surface,
                        hintText: 'Buscar por nombre, código o correo',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () =>
                                    setState(() => _search.clear()),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (filter, label, count) in [
                          (_Filter.all, 'Todos', all.length),
                          (_Filter.active, 'Activos', activeCount),
                          (_Filter.withdrawn, 'Retirados', withdrawnCount),
                        ]) ...[
                          _FilterPill(
                            label: label,
                            count: count,
                            selected: _filter == filter,
                            onTap: () => setState(() => _filter = filter),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Estudiantes registrados '
                          '(${visible.length} '
                          '${visible.length == 1 ? 'mostrado' : 'mostrados'})',
                          style: text.labelMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.sort_by_alpha,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'A–Z',
                        style: text.labelMedium?.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (visible.isEmpty)
                    EmptyState(
                      icon: Icons.group_off_outlined,
                      title: all.isEmpty
                          ? 'Aún no hay estudiantes'
                          : 'Sin resultados',
                      message: all.isEmpty
                          ? 'Agrégalos uno por uno o importa un archivo.'
                          : 'Prueba con otra búsqueda o filtro.',
                    ),
                  FutureBuilder<CourseReportData>(
                    future: _report,
                    builder: (context, reportSnap) => Column(
                      children: [
                        for (final enrollment in visible) ...[
                          _StudentTile(
                            enrollment: enrollment,
                            stats: reportSnap.data
                                ?.rowFor(enrollment.email)
                                ?.stats,
                            canReactivate: acceptsStudents,
                            onOpen: () => _openFile(enrollment),
                            onGrade: () => _editGrade(enrollment),
                            onWithdraw: () => _withdraw(
                              enrollment,
                              reportSnap.data?.rowFor(enrollment.email)?.stats,
                            ),
                            onReactivate: () => _reactivate(enrollment),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ImportCard(
                    onImport: acceptsStudents ? _import : null,
                    onHelp: _showFormatHelp,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.enrollment,
    required this.stats,
    required this.canReactivate,
    required this.onOpen,
    required this.onGrade,
    required this.onWithdraw,
    required this.onReactivate,
  });

  final Enrollment enrollment;
  final StudentStats? stats;
  final bool canReactivate;
  final VoidCallback onOpen;
  final VoidCallback onGrade;
  final VoidCallback onWithdraw;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final active = enrollment.isActive;
    final stats = this.stats;
    final hasStats = active && stats != null && stats.total > 0;
    final risk = hasStats ? stats.risk : RiskLevel.ok;
    final (Color tone, Color toneBg) = !active
        ? (AppColors.textMuted, AppColors.surfaceVariant)
        : switch (risk) {
            RiskLevel.ok => (AppColors.present, AppColors.presentContainer),
            RiskLevel.warning => (AppColors.late, AppColors.lateContainer),
            RiskLevel.exceeded => (AppColors.absent, AppColors.absentContainer),
          };
    final grade = enrollment.grade;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: Stack(
                      children: [
                        PhotoOrInitials(
                          name: enrollment.name,
                          email: enrollment.email,
                          size: 44,
                          background: toneBg,
                          foreground: tone,
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(
                              color: tone,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          enrollment.name,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${enrollment.studentCode} · ${enrollment.email}',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textMuted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!active)
                    const StatusChip(
                      label: 'Retirado',
                      foreground: AppColors.textMuted,
                      background: AppColors.surfaceVariant,
                    )
                  else if (risk == RiskLevel.ok)
                    const StatusChip(
                      label: 'Activo',
                      icon: Icons.check,
                      foreground: AppColors.present,
                      background: AppColors.presentContainer,
                    )
                  else
                    RiskChip(level: risk, compact: true),
                ],
              ),
              if (hasStats || grade != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 56),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasStats)
                        StatusChip(
                          label:
                              '${percent(stats.attendanceRate)} asist. '
                              '(${stats.total - stats.absent}/${stats.total})',
                          icon: Icons.how_to_reg_outlined,
                          foreground: tone,
                          background: toneBg,
                        ),
                      if (hasStats)
                        Text(
                          'Faltas: ${stats.absent}',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      if (grade != null)
                        Text(
                          'Definitiva: ${grade.toStringAsFixed(1)}',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (risk == RiskLevel.exceeded && active) ...[
                const SizedBox(height: 8),
                NoticeBox(
                  icon: Icons.warning_amber_rounded,
                  color: AppColors.late,
                  background: AppColors.lateContainer,
                  child: Text(
                    'Superó el '
                    '${percent(AppConfig.maxAbsenceRate)} de inasistencias '
                    'no justificadas.',
                  ),
                ),
              ],
              if (!active && enrollment.withdrawReason != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Motivo: ${enrollment.withdrawReason!.label}'
                  '${enrollment.withdrawNote == null ? '' : ' · ${enrollment.withdrawNote}'}',
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              InsetPanel(
                padding: const EdgeInsets.all(6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: _ActionChip(
                        icon: Icons.edit_note,
                        label: grade == null
                            ? 'Nota'
                            : 'Nota: ${grade.toStringAsFixed(1)}',
                        onTap: onGrade,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: active
                          ? _ActionChip(
                              icon: Icons.person_remove_outlined,
                              label: 'Dar de baja',
                              color: AppColors.absent,
                              background: AppColors.absentContainer,
                              onTap: onWithdraw,
                            )
                          : _ActionChip(
                              icon: Icons.undo,
                              label: 'Reactivar',
                              onTap: canReactivate ? onReactivate : null,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón pequeño de la barra de acciones de un estudiante.
class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textSecondary,
    this.background = AppColors.surface,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: enabled ? color : AppColors.outlineVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: enabled ? color : AppColors.outlineVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resumen del grupo y botón para agregar estudiantes.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.course,
    required this.active,
    required this.withdrawn,
    required this.atRisk,
    required this.onAdd,
  });

  final Course? course;
  final int active;
  final int withdrawn;
  final int? atRisk;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final course = this.course;
    final total = active + withdrawn;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (course != null)
                        StatusChip(
                          label: 'Periodo ${course.period}',
                          dot: true,
                          foreground: AppColors.present,
                          background: AppColors.presentContainer,
                        ),
                      const SizedBox(height: 6),
                      Text('Gestión de estudiantes', style: text.headlineSmall),
                      if (course != null)
                        Text(
                          '${course.name} · ${course.group}',
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                const IconBadge(
                  icon: Icons.school_outlined,
                  color: AppColors.primaryDark,
                  background: AppColors.surfaceVariant,
                  size: 44,
                ),
              ],
            ),
            const SizedBox(height: 12),
            InsetPanel(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$active',
                        style: text.headlineSmall?.copyWith(
                          color: AppColors.primaryDark,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text('activos', style: text.titleSmall),
                      const Spacer(),
                      Text(
                        '$withdrawn '
                        '${withdrawn == 1 ? 'retirado' : 'retirados'}',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : active / total,
                      minHeight: 8,
                      color: AppColors.primaryDark,
                      backgroundColor: AppColors.surfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 15,
                        color: AppColors.present,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '$total en la lista',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.present,
                          ),
                        ),
                      ),
                      if (atRisk != null && atRisk! > 0) ...[
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 15,
                          color: AppColors.late,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$atRisk en riesgo',
                          style: text.labelSmall?.copyWith(
                            color: AppColors.tertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
              ),
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Agregar estudiante'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Píldora de filtro con su cantidad.
class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final fg = selected ? Colors.white : AppColors.textSecondary;
    return Material(
      color: selected ? AppColors.primaryDark : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.primaryDark : AppColors.outline,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: text.labelLarge?.copyWith(color: fg)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: text.labelSmall?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta para importar la lista completa desde un archivo.
class _ImportCard extends StatelessWidget {
  const _ImportCard({required this.onImport, required this.onHelp});

  final VoidCallback? onImport;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(
                  icon: Icons.upload_file,
                  color: AppColors.present,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Importación masiva',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sube la lista tal como la descargas de la plataforma de la '
              'universidad (.xls), o un archivo .xlsx o .csv.',
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceVariant,
                      foregroundColor: AppColors.primaryDark,
                      minimumSize: const Size.fromHeight(44),
                      textStyle: text.labelLarge,
                    ),
                    onPressed: onImport,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Importar lista'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.surfaceVariant,
                      foregroundColor: AppColors.primaryDark,
                      minimumSize: const Size.fromHeight(44),
                      textStyle: text.labelLarge,
                    ),
                    onPressed: onHelp,
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: const Text('Formato'),
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

/// Formulario para inscribir a un estudiante.
class _AddStudentSheet extends StatefulWidget {
  const _AddStudentSheet({required this.courseId});

  final String courseId;

  @override
  State<_AddStudentSheet> createState() => _AddStudentSheetState();
}

class _AddStudentSheetState extends State<_AddStudentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _checking = false;
  bool _saving = false;

  /// Si el correo ya tiene pre-registro, el código queda fijo.
  bool _codeLocked = false;
  String? _info;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final email = Validators.normalizeEmail(_email.text);
    if (Validators.institutionalEmail(email) != null) {
      _formKey.currentState!.validate();
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
      _info = null;
    });
    try {
      final pre = await context.read<CourseRepository>().getPreRegistration(
        email,
      );
      if (!mounted) return;
      setState(() {
        if (pre == null) {
          _codeLocked = false;
          _info = 'Estudiante nuevo: completa su nombre y código.';
        } else {
          _name.text = pre.name;
          _code.text = pre.studentCode;
          _codeLocked = true;
          _info = 'Este estudiante ya fue registrado antes; usamos sus datos.';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = AuthService.messageFor(e));
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final student = RosterEntry(
      email: Validators.normalizeEmail(_email.text),
      name: _name.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      studentCode: _code.text.trim(),
    );
    try {
      final outcome = await context.read<CourseRepository>().enrollStudent(
        courseId: widget.courseId,
        teacherId: context.read<AuthProvider>().profile!.uid,
        student: student,
      );
      if (!mounted) return;
      Navigator.pop(
        context,
        outcome == EnrollOutcome.added
            ? '${student.name} fue inscrito.'
            : '${student.name} volvió a estar activo.',
      );
      return;
    } on AlreadyEnrolledException {
      _error = 'Este estudiante ya está inscrito en el curso.';
    } on CodeConflictException catch (e) {
      _error =
          'Este correo ya está registrado con el código '
          '${e.registeredCode}. Verifica los datos.';
    } catch (e) {
      _error = AuthService.messageFor(e);
    }
    if (mounted) setState(() => _saving = false);
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
                Text('Inscribir estudiante', style: text.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'El estudiante creará su cuenta con este correo y código.',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                const FieldLabel('Correo institucional'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        validator: Validators.institutionalEmail,
                        onChanged: (_) {
                          if (_codeLocked || _info != null) {
                            setState(() {
                              _codeLocked = false;
                              _info = null;
                            });
                          }
                        },
                        onFieldSubmitted: (_) => _lookup(),
                        decoration: const InputDecoration(
                          hintText: 'usuario@${AppConfig.institutionalDomain}',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        onPressed: _checking ? null : _lookup,
                        child: _checking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Validar'),
                      ),
                    ),
                  ],
                ),
                if (_info != null) ...[
                  const SizedBox(height: 8),
                  MessageBanner(_info!, kind: BannerKind.info),
                ],
                const SizedBox(height: 12),
                const FieldLabel('Nombre completo'),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  validator: Validators.fullName,
                  decoration: const InputDecoration(
                    hintText: 'Nombres y apellidos',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 12),
                const FieldLabel('Código estudiantil'),
                TextFormField(
                  controller: _code,
                  readOnly: _codeLocked,
                  keyboardType: TextInputType.number,
                  validator: Validators.studentCode,
                  decoration: const InputDecoration(
                    hintText: 'Ej. 20231145028',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  MessageBanner(_error!),
                ],
                const SizedBox(height: 20),
                LoadingButton(
                  label: 'Confirmar inscripción',
                  icon: Icons.check,
                  loading: _saving,
                  onPressed: _submit,
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// D8b · Confirmar baja de un estudiante.
class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.enrollment, this.stats});

  final Enrollment enrollment;
  final StudentStats? stats;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _note = TextEditingController();
  WithdrawReason? _reason;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_reason == null) {
      setState(() => _error = 'Selecciona el motivo de la baja.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<CourseRepository>().withdrawStudent(
        courseId: widget.enrollment.courseId,
        email: widget.enrollment.email,
        reason: _reason!,
        note: _note.text,
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
    final e = widget.enrollment;
    final stats = widget.stats;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const IconBadge(
                    icon: Icons.person_remove_outlined,
                    color: AppColors.absent,
                    background: AppColors.absentContainer,
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '¿Dar de baja a este estudiante?',
                          style: text.headlineSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Se desvinculará del curso y no podrá marcar '
                          'asistencia. Su historial se conserva y puedes '
                          'reactivarlo después.',
                          style: text.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              InsetPanel(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        PersonAvatar(name: e.name, email: e.email, size: 44),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.name,
                                style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${e.studentCode} · ${e.email}',
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (stats != null &&
                            stats.total > 0 &&
                            stats.risk != RiskLevel.ok)
                          RiskChip(level: stats.risk, compact: true),
                      ],
                    ),
                    if (stats != null &&
                        stats.total > 0 &&
                        stats.risk == RiskLevel.exceeded) ...[
                      const SizedBox(height: 10),
                      NoticeBox(
                        icon: Icons.warning_rounded,
                        color: AppColors.absent,
                        background: AppColors.absentContainer,
                        title:
                            'Superó el ${percent(AppConfig.maxAbsenceRate)} '
                            'de inasistencias',
                        child: Text(
                          '${stats.absent} '
                          '${stats.absent == 1 ? 'falta acumulada' : 'faltas acumuladas'}'
                          ' · ${percent(stats.attendanceRate)} de asistencia',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Motivo de la baja'),
              for (final reason in WithdrawReason.values) ...[
                _ReasonOption(
                  reason: reason,
                  selected: _reason == reason,
                  onTap: () => setState(() => _reason = reason),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 8),
              const FieldLabel('Observaciones'),
              TextField(
                controller: _note,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Ej. número de acta o detalle de la solicitud',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                MessageBanner(_error!),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.absent,
                  shape: const StadiumBorder(),
                ),
                onPressed: _saving ? null : _confirm,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_remove_outlined),
                label: const Text('Confirmar baja'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar y conservar en la lista'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Motivo de baja como tarjeta con ícono y marca de selección.
class _ReasonOption extends StatelessWidget {
  const _ReasonOption({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final WithdrawReason reason;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final icon = switch (reason) {
      WithdrawReason.absences => Icons.gavel,
      WithdrawReason.voluntary => Icons.exit_to_app,
      WithdrawReason.registrationError => Icons.sync_problem,
    };
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? AppColors.primaryContainer.withValues(alpha: 0.6)
            : AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.primaryDark : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primaryDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reason.label,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        reason.description,
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected
                      ? AppColors.primaryDark
                      : AppColors.outlineVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vista previa e inscripción masiva desde un archivo.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({
    required this.courseId,
    required this.fileName,
    required this.result,
  });

  final String courseId;
  final String fileName;
  final RosterParseResult result;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  bool _running = false;
  int _done = 0;
  ImportReport? _report;

  Future<void> _run() async {
    setState(() => _running = true);
    final report = await context.read<CourseRepository>().enrollMany(
      courseId: widget.courseId,
      teacherId: context.read<AuthProvider>().profile!.uid,
      students: widget.result.entries,
      onProgress: (done, _) {
        if (mounted) setState(() => _done = done);
      },
    );
    if (mounted) {
      setState(() {
        _running = false;
        _report = report;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final report = _report;
    final total = result.entries.length;

    if (report != null) {
      return AlertDialog(
        title: const Text('Importación terminada'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Inscritos: ${report.added}'),
              Text('Reactivados: ${report.reactivated}'),
              Text('Omitidos: ${report.skipped.length}'),
              if (report.skipped.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final line in report.skipped)
                  Text('• $line', style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(widget.fileName, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_running) ...[
              LinearProgressIndicator(value: total == 0 ? null : _done / total),
              const SizedBox(height: 8),
              Text('Inscribiendo $_done de $total…'),
            ] else ...[
              Text(
                total == 0
                    ? 'No se encontraron estudiantes válidos.'
                    : 'Se inscribirán $total estudiantes.',
              ),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${result.errors.length} filas con problemas (se omitirán):',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                for (final error in result.errors.take(20))
                  Text('• $error', style: const TextStyle(fontSize: 13)),
                if (result.errors.length > 20)
                  Text('… y ${result.errors.length - 20} más.'),
              ],
            ],
          ],
        ),
      ),
      actions: _running
          ? const []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              if (total > 0)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  onPressed: _run,
                  child: const Text('Inscribir'),
                ),
            ],
    );
  }
}

/// Diálogo para la nota definitiva. Es un widget con estado para que el
/// controlador del texto viva lo mismo que el diálogo (incluida su animación
/// de cierre).
class _GradeDialog extends StatefulWidget {
  const _GradeDialog({required this.enrollment});

  final Enrollment enrollment;

  @override
  State<_GradeDialog> createState() => _GradeDialogState();
}

class _GradeDialogState extends State<_GradeDialog> {
  late final _controller = TextEditingController(
    text: widget.enrollment.grade?.toStringAsFixed(1) ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nota definitiva · ${widget.enrollment.name}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          hintText: 'De 0.0 a 5.0 (vacío para borrar)',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
