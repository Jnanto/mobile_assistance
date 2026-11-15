import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_session.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/report_export.dart';
import '../../../data/services/report_loader.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../auth/providers/auth_provider.dart';

/// E3 · Resultado del registro de asistencia.
class AttendanceResultScreen extends StatefulWidget {
  const AttendanceResultScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<AttendanceResultScreen> createState() => _AttendanceResultScreenState();
}

class _AttendanceResultScreenState extends State<AttendanceResultScreen> {
  late final AttendanceRepository _repo = context.read<AttendanceRepository>();
  late final Stream<ClassSession?> _session = _repo.watchSession(
    widget.sessionId,
  );
  late final Stream<AttendanceRecord?> _record = _repo.watchMyRecord(
    widget.sessionId,
    context.read<AuthProvider>().profile?.email ?? '',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asistencia registrada'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<ClassSession?>(
        stream: _session,
        builder: (context, sessionSnap) => StreamBuilder<AttendanceRecord?>(
          stream: _record,
          builder: (context, recordSnap) {
            final session = sessionSnap.data;
            final record = recordSnap.data;
            if (session == null || record == null) {
              final failed = sessionSnap.hasError || recordSnap.hasError;
              return failed
                  ? const EmptyState(
                      icon: Icons.error_outline,
                      title: 'No se pudo cargar tu registro',
                      message: 'Revisa tu conexión.',
                    )
                  : const Center(child: CircularProgressIndicator());
            }
            return _Result(session: session, record: record);
          },
        ),
      ),
    );
  }
}

class _Result extends StatefulWidget {
  const _Result({required this.session, required this.record});

  final ClassSession session;
  final AttendanceRecord record;

  @override
  State<_Result> createState() => _ResultState();
}

class _ResultState extends State<_Result> {
  late final Future<StudentFileData> _summary = loadStudentFile(
    courses: context.read<CourseRepository>(),
    attendance: context.read<AttendanceRepository>(),
    courseId: widget.session.courseId,
    email: widget.record.email,
    asTeacher: false,
  );
  bool _showReceipt = false;

  /// Identificador corto del registro: clase + código del estudiante.
  String get _receipt {
    final session = widget.session.id;
    final short = session.length > 6 ? session.substring(0, 6) : session;
    final code = widget.record.studentCode;
    final tail = code.length > 4 ? code.substring(code.length - 4) : code;
    return '${short.toUpperCase()}-$tail';
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final record = widget.record;
    final text = Theme.of(context).textTheme;
    final status = record.statusFor(session);
    final style = attendanceStyle(status);
    final (String title, String message) = switch (status) {
      AttendanceStatus.review => (
        'Registro enviado',
        'Tu asistencia quedó "Por revisar": tu docente la confirmará.',
      ),
      AttendanceStatus.absent => (
        'Registro rechazado',
        'Tu docente rechazó este registro. Si crees que es un error, '
            'habla con tu docente.',
      ),
      _ => (
        '¡Listo!',
        'Tu asistencia quedó verificada y registrada con la hora del '
            'servidor.',
      ),
    };
    final markedAt = record.markedAt;
    final onTime = status == AttendanceStatus.present;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.surface, style.bg],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: Stack(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: style.fg,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: style.fg.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(
                          status == AttendanceStatus.present ||
                                  status == AttendanceStatus.late
                              ? Icons.check_rounded
                              : style.icon,
                          size: 52,
                          color: Colors.white,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: status == AttendanceStatus.present
                                ? const Color(0xFFA3F69C)
                                : style.bg,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: text.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                StatusChip(
                  label: onTime ? 'Presente · Puntual' : style.label,
                  icon: style.icon,
                  foreground: style.fg,
                  background: AppColors.surface,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<StudentFileData>(
          future: _summary,
          builder: (context, snap) {
            final stats = snap.data?.stats;
            if (stats == null || stats.total == 0) {
              return const SizedBox.shrink();
            }
            final attended = stats.total - stats.absent;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: stats.attendanceRate,
                            strokeWidth: 5,
                            color: AppColors.present,
                            backgroundColor: AppColors.surfaceVariant,
                          ),
                          const Icon(
                            Icons.trending_up,
                            color: AppColors.present,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Asistencia acumulada: '
                            '${percent(stats.attendanceRate)}',
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Has asistido a $attended de ${stats.total} '
                            'clases dictadas.',
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
            );
          },
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
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Detalle del registro',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusChip(
                      label: 'Comprobante #$_receipt',
                      foreground: AppColors.textSecondary,
                      background: AppColors.surfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                InsetPanel(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ASIGNATURA',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        session.courseName,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Clase #${session.number} · Sesión presencial',
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  icon: Icons.person_outline,
                  label: 'Docente',
                  value: session.teacherName.isEmpty
                      ? '—'
                      : 'Prof. ${session.teacherName}',
                ),
                _DetailRow(
                  icon: Icons.schedule,
                  label: 'Hora de registro',
                  value: markedAt == null
                      ? 'enviando…'
                      : ScheduleFormat.clock(markedAt),
                  note: switch (record.timingStatus(session)) {
                    AttendanceStatus.present =>
                      'Dentro del tiempo para Presente',
                    AttendanceStatus.late => 'En la ventana de Tarde',
                    _ => null,
                  },
                ),
                const Divider(height: 20),
                _CheckRow(label: 'Código QR de la clase', ok: true),
                _CheckRow(
                  label: record.gpsOk
                      ? 'GPS dentro del aula'
                      : 'GPS: ${record.mockedLocation ? 'ubicación simulada' : 'fuera del perímetro o no disponible'}',
                  ok: record.gpsOk,
                ),
                _CheckRow(
                  label: !session.wifiRequired
                      ? 'WiFi no exigido'
                      : record.wifiOk
                      ? 'WiFi del aula'
                      : 'WiFi: no conectado a la red del aula',
                  ok: record.wifiOk,
                ),
                const SizedBox(height: 8),
                Material(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _showReceipt = !_showReceipt),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_2, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Ver comprobante',
                              style: text.titleSmall?.copyWith(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Icon(
                            _showReceipt
                                ? Icons.expand_less
                                : Icons.expand_more,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showReceipt) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: QrImageView(
                      data: record.id,
                      size: 150,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.primaryDark,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    record.id,
                    textAlign: TextAlign.center,
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
            shape: const StadiumBorder(),
          ),
          onPressed: () => context.go(Routes.studentHome),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver a mis cursos'),
        ),
        const SizedBox(height: 16),
        Text(
          'Universidad de la Amazonia · Florencia, Caquetá',
          textAlign: TextAlign.center,
          style: text.labelSmall?.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (note != null)
                Text(
                  note!,
                  style: text.labelSmall?.copyWith(color: AppColors.present),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: ok ? AppColors.present : AppColors.review,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
