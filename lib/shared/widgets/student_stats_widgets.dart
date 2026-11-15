import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/schedule_format.dart';
import '../../data/models/attendance_record.dart';
import '../../data/services/attendance_stats.dart';
import '../../data/services/report_export.dart';
import 'common_widgets.dart';
import 'report_charts.dart';

/// Encabezado con el resumen de un estudiante (D7 y E5): anillo de
/// asistencia, estado frente al límite y cifras por estado.
class StudentStatsHeader extends StatelessWidget {
  const StudentStatsHeader({
    super.key,
    required this.name,
    required this.subtitle,
    required this.stats,
    this.title = 'Métricas de asistencia',
    this.leading,
  });

  final String name;
  final String subtitle;
  final StudentStats stats;
  final String title;

  /// Avatar u otro elemento a la izquierda del nombre.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasData = stats.total > 0;
    final rateColor = !hasData
        ? AppColors.textMuted
        : switch (stats.risk) {
            RiskLevel.ok => AppColors.present,
            RiskLevel.warning => AppColors.late,
            RiskLevel.exceeded => AppColors.absent,
          };
    final attended = stats.total - stats.absent;
    final explanation = switch (stats.risk) {
      _ when !hasData => 'Aún no hay clases dictadas.',
      RiskLevel.ok => 'Al día con el reglamento de asistencia.',
      RiskLevel.warning => 'Se acerca al límite de inasistencia.',
      RiskLevel.exceeded => 'Superó el límite de inasistencia.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: text.headlineSmall),
                  Text(
                    subtitle,
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.insights,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                InsetPanel(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        height: 92,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox.expand(
                              child: CircularProgressIndicator(
                                value: hasData ? stats.attendanceRate : 0,
                                strokeWidth: 8,
                                strokeCap: StrokeCap.round,
                                color: rateColor,
                                backgroundColor: AppColors.surfaceVariant,
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  hasData ? percent(stats.attendanceRate) : '—',
                                  style: text.titleLarge?.copyWith(
                                    color: rateColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'Asistencia',
                                  style: text.labelSmall?.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RiskChip(level: stats.risk),
                            const SizedBox(height: 6),
                            Text(
                              explanation,
                              style: text.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              hasData
                                  ? '$attended de ${stats.total} clases sin '
                                        'falta · ${stats.absent} '
                                        '${stats.absent == 1 ? 'falta' : 'faltas'} '
                                        '(${percent(stats.absenceRate)}). '
                                        'Límite: '
                                        '${percent(AppConfig.maxAbsenceRate)}.'
                                  : 'Límite de inasistencia: '
                                        '${percent(AppConfig.maxAbsenceRate)}.',
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
                const SizedBox(height: 10),
                for (final pair in [
                  [
                    (AttendanceStatus.present, stats.present),
                    (AttendanceStatus.late, stats.late),
                  ],
                  [
                    (AttendanceStatus.absent, stats.absent),
                    (AttendanceStatus.justified, stats.justified),
                  ],
                ]) ...[
                  Row(
                    children: [
                      for (final (status, count) in pair) ...[
                        Expanded(
                          child: _CountTile(status: status, count: count),
                        ),
                        if (status == pair.first.$1) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  if (pair.first.$1 == AttendanceStatus.present)
                    const SizedBox(height: 8),
                ],
                if (stats.review > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${stats.review} registro(s) por revisar (cuentan como '
                    'asistencia hasta que el docente decida).',
                    style: text.bodySmall?.copyWith(color: AppColors.review),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Cifra de un estado con su ícono en un cuadrado de color.
class _CountTile extends StatelessWidget {
  const _CountTile({required this.status, required this.count});

  final AttendanceStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = attendanceStyle(status);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: style.fg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(style.icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: text.titleMedium?.copyWith(
                    color: style.fg,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  style.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(color: style.fg),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Una clase del historial (D7 y E5).
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry, this.trailingAction});

  final HistoryEntry entry;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final record = entry.record;
    final markedAt = record?.markedAt;
    final style = attendanceStyle(entry.status);
    final details = <String>[
      if (record == null)
        'Sin registro en el aula'
      else if (markedAt != null)
        'Registró a las ${ScheduleFormat.clock(markedAt)}',
      if (record?.manualStatus != null)
        'Corrección manual: ${record!.manualReason ?? ''}',
      if (record != null &&
          record.manualStatus == null &&
          record.review != ReviewStatus.notRequired)
        record.reviewReasons.join(' · '),
    ].where((s) => s.isNotEmpty).toList();
    final start = entry.session.startedAt;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '#${entry.session.number}',
                style: text.titleSmall?.copyWith(
                  color: style.fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${start.day} ${ScheduleFormat.monthShort(start)} '
                    '${start.year} · ${ScheduleFormat.weekday(start)}',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  for (final line in details)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2, right: 4),
                          child: Icon(
                            record == null ? Icons.alarm_off : Icons.alarm,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            line,
                            style: text.bodySmall?.copyWith(
                              color: AppColors.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AttendanceChip(status: entry.status),
                ?trailingAction,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
