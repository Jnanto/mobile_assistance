import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/attendance_record.dart';
import '../../data/services/attendance_stats.dart';
import 'common_widgets.dart';

/// Una barra del gráfico de asistencia por clase.
class RateBar {
  const RateBar({
    required this.label,
    required this.rate,
    required this.detail,
  });

  /// Etiqueta corta bajo la barra ("C3").
  final String label;

  /// 0 a 1.
  final double rate;

  /// Texto completo al tocar la barra.
  final String detail;
}

/// Columnas de asistencia por clase (una sola serie: sin leyenda).
///
/// Barras de 20 px con extremo redondeado de 4 px, separadas por aire;
/// cuadrícula fina y una línea de referencia en el mínimo de asistencia
/// (1 − límite de inasistencia). Al tocar una barra se muestra su detalle.
class AttendanceBarChart extends StatefulWidget {
  const AttendanceBarChart({super.key, required this.bars, this.height = 180});

  final List<RateBar> bars;
  final double height;

  @override
  State<AttendanceBarChart> createState() => _AttendanceBarChartState();
}

class _AttendanceBarChartState extends State<AttendanceBarChart> {
  int? _selected;

  static const _barWidth = 26.0;
  static const _slot = 38.0;
  static const _axisWidth = 48.0;

  @override
  void initState() {
    super.initState();
    // Por defecto se resalta la clase más reciente.
    if (widget.bars.isNotEmpty) _selected = widget.bars.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.labelSmall?.copyWith(color: AppColors.textMuted);
    final plotHeight = widget.height;
    final minRate = 1 - AppConfig.maxAbsenceRate;
    final selected = _selected == null ? null : widget.bars[_selected!];

    Widget gridLine(double rate, String label, {Color? color}) => Positioned(
      left: 0,
      right: 0,
      bottom: plotHeight * rate,
      child: Row(
        children: [
          SizedBox(
            width: _axisWidth,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: muted?.copyWith(color: color),
            ),
          ),
          Expanded(
            child: Container(height: 1, color: color ?? AppColors.gridLine),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 36,
          child: selected == null
              ? null
              : Text(
                  selected.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: plotHeight + 24,
          child: Stack(
            children: [
              Positioned.fill(
                bottom: 24,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    gridLine(0, '0 %'),
                    gridLine(0.5, '50 %'),
                    gridLine(1, '100 %'),
                    gridLine(
                      minRate,
                      '${(minRate * 100).round()} %',
                      color: AppColors.absent,
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                left: _axisWidth,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < widget.bars.length; i++)
                        _bar(i, plotHeight, muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _axisWidth, top: 4),
          child: Text(
            'Línea roja: mínimo de asistencia '
            '(${(minRate * 100).round()} %). Toca una barra para ver el '
            'detalle.',
            style: muted,
          ),
        ),
      ],
    );
  }

  Widget _bar(int i, double plotHeight, TextStyle? muted) {
    final bar = widget.bars[i];
    final isSelected = _selected == i;
    final belowMin = bar.rate < 1 - AppConfig.maxAbsenceRate;
    return Semantics(
      label: bar.detail,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = i),
        child: SizedBox(
          width: _slot,
          height: plotHeight + 24,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${(bar.rate * 100).round()}%',
                maxLines: 1,
                softWrap: false,
                style: muted?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: belowMin ? AppColors.late : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                width: _barWidth,
                height: (plotHeight * bar.rate.clamp(0, 1)).clamp(
                  2,
                  plotHeight - 16,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryDark
                      : (belowMin
                            ? AppColors.present.withValues(alpha: 0.5)
                            : AppColors.present),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ),
              SizedBox(
                height: 24,
                child: Center(
                  child: Text(
                    bar.label,
                    style: muted?.copyWith(
                      fontWeight: isSelected ? FontWeight.w700 : null,
                      color: isSelected ? AppColors.textPrimary : null,
                    ),
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

/// Cantidad por estado para la barra apilada.
class StatusCount {
  const StatusCount(this.status, this.count);

  final AttendanceStatus status;
  final int count;
}

/// Orden validado para que cada segmento contraste con sus vecinos.
const stackedStatusOrder = [
  AttendanceStatus.present,
  AttendanceStatus.review,
  AttendanceStatus.late,
  AttendanceStatus.justified,
  AttendanceStatus.absent,
];

Color statusChartColor(AttendanceStatus status) => switch (status) {
  AttendanceStatus.review => AppColors.reviewChart,
  _ => attendanceStyle(status).fg,
};

/// Barra horizontal apilada con la distribución de estados, separada por
/// espacios de 2 px, y una leyenda con ícono, etiqueta, cantidad y porcentaje
/// (el color nunca es la única señal).
class StatusDistributionBar extends StatelessWidget {
  const StatusDistributionBar({super.key, required this.counts});

  final List<StatusCount> counts;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = counts.fold(0, (sum, c) => sum + c.count);
    final ordered = [
      for (final status in stackedStatusOrder)
        counts.firstWhere(
          (c) => c.status == status,
          orElse: () => StatusCount(status, 0),
        ),
    ];
    final visible = ordered.where((c) => c.count > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 20,
            child: total == 0
                ? Container(color: AppColors.gridLine)
                : Row(
                    children: [
                      for (var i = 0; i < visible.length; i++) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: visible[i].count,
                          child: Container(
                            color: statusChartColor(visible[i].status),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 12),
        for (final c in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusChartColor(c.status),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  attendanceStyle(c.status).icon,
                  size: 16,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    attendanceStyle(c.status).label,
                    style: text.bodyMedium,
                  ),
                ),
                Text(
                  '${c.count}',
                  style: text.bodyMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    total == 0 ? '—' : '${(c.count * 100 / total).round()} %',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.fade,
                    textAlign: TextAlign.right,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Dona con la distribución de estados y, debajo, una cifra por estado
/// (ícono, etiqueta, cantidad y porcentaje: el color no es la única señal).
class StatusDonut extends StatelessWidget {
  const StatusDonut({
    super.key,
    required this.counts,
    required this.centerValue,
    required this.centerLabel,
  });

  final List<StatusCount> counts;
  final String centerValue;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = counts.fold(0, (sum, c) => sum + c.count);
    final ordered = [
      for (final status in stackedStatusOrder)
        counts.firstWhere(
          (c) => c.status == status,
          orElse: () => StatusCount(status, 0),
        ),
    ];
    final tiles = ordered
        .where((c) => c.status != AttendanceStatus.review || c.count > 0)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              painter: _DonutPainter(ordered, total),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerValue,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      centerLabel,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _StatusShareTile(count: tiles[i], total: total),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: i + 1 < tiles.length
                    ? _StatusShareTile(count: tiles[i + 1], total: total)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StatusShareTile extends StatelessWidget {
  const _StatusShareTile({required this.count, required this.total});

  final StatusCount count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = attendanceStyle(count.status);
    final color = statusChartColor(count.status);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(style.icon, size: 18, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  style.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  total == 0
                      ? '—'
                      : '${(count.count * 100 / total).round()} % · '
                            '${count.count}',
                  style: text.titleSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.counts, this.total);

  final List<StatusCount> counts;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total == 0) {
      canvas.drawArc(
        rect,
        0,
        2 * math.pi,
        false,
        paint..color = AppColors.gridLine,
      );
      return;
    }
    const gap = 0.03;
    var start = -math.pi / 2;
    final visible = counts.where((c) => c.count > 0).toList();
    for (final c in visible) {
      final sweep = 2 * math.pi * c.count / total;
      final drawn = visible.length > 1 ? sweep - gap : sweep;
      canvas.drawArc(
        rect,
        start,
        drawn,
        false,
        paint..color = statusChartColor(c.status),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.total != total || old.counts != counts;
}

/// Chip de riesgo de inasistencia.
class RiskChip extends StatelessWidget {
  const RiskChip({super.key, required this.level, this.compact = false});

  final RiskLevel level;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return switch (level) {
      RiskLevel.exceeded => StatusChip(
        label: compact ? 'Superó' : 'Superó el límite',
        icon: Icons.report_outlined,
        foreground: AppColors.absent,
        background: AppColors.absentContainer,
      ),
      RiskLevel.warning => StatusChip(
        label: compact ? 'En riesgo' : 'Cerca del límite',
        icon: Icons.warning_amber,
        foreground: AppColors.review,
        background: AppColors.reviewContainer,
      ),
      RiskLevel.ok => const StatusChip(
        label: 'Al día',
        icon: Icons.verified_outlined,
        foreground: AppColors.present,
        background: AppColors.presentContainer,
      ),
    };
  }
}
