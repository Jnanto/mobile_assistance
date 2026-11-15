import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Ícono dentro de un cuadrado redondeado con fondo tenue de su color.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color = AppColors.primary,
    this.size = 40,
    this.background,
  });

  final IconData icon;
  final Color color;
  final double size;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, size: size * 0.55, color: color),
    );
  }
}

/// Anillo de cuenta regresiva con el tiempo en grande.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.progress,
    required this.time,
    required this.caption,
    this.color = AppColors.primaryDark,
    this.size = 180,
    this.footer,
  });

  /// Fracción que queda (1 = todo el tiempo, 0 = vencido).
  final double progress;
  final String time;
  final String caption;
  final Color color;
  final double size;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress.clamp(0, 1).toDouble(), color),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    time,
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.8,
                  ),
                ),
                if (footer != null) ...[const SizedBox(height: 4), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final track = Paint()
      ..color = AppColors.surfaceVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arcRect, 0, math.pi * 2, false, track);
    if (progress > 0) {
      canvas.drawArc(arcRect, -math.pi / 2, math.pi * 2 * progress, false, arc);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// Estado de una validación en una fila.
enum CheckState { ok, warning, failed, pending, loading }

/// Tarjeta con una validación (GPS, WiFi, QR): ícono, título, etiqueta,
/// descripción y estado a la derecha.
class ValidationTile extends StatelessWidget {
  const ValidationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.state,
    this.tag,
    this.footer,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final CheckState state;

  /// Etiqueta junto al título (p. ej. "Radio 40 m").
  final String? tag;
  final Widget? footer;

  /// Reemplaza el indicador de estado (p. ej. un botón de reintentar).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (color, background) = switch (state) {
      CheckState.ok => (AppColors.present, AppColors.presentContainer),
      CheckState.warning => (AppColors.tertiary, AppColors.lateContainer),
      CheckState.failed => (AppColors.absent, AppColors.absentContainer),
      CheckState.pending ||
      CheckState.loading => (AppColors.primary, AppColors.surfaceVariant),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon: icon, color: color, background: background),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (tag != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: background,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag!,
                            style: text.labelSmall?.copyWith(color: color),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: text.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (footer != null) ...[const SizedBox(height: 6), footer!],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ?? _StateMark(state: state),
          ],
        ),
      ),
    );
  }
}

class _StateMark extends StatelessWidget {
  const _StateMark({required this.state});

  final CheckState state;

  @override
  Widget build(BuildContext context) => switch (state) {
    CheckState.ok => const Icon(Icons.check_circle, color: AppColors.present),
    CheckState.warning => const Icon(Icons.error, color: AppColors.late),
    CheckState.failed => const Icon(Icons.cancel, color: AppColors.absent),
    CheckState.pending => const Icon(
      Icons.radio_button_unchecked,
      color: AppColors.outlineVariant,
    ),
    CheckState.loading => const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    ),
  };
}

/// Selector en píldora: el elegido se ve como una tarjeta blanca elevada.
class PillSegments<T> extends StatelessWidget {
  const PillSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: Semantics(
                selected: value == selected,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onChanged == null ? null : () => onChanged!(value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: value == selected ? AppColors.surface : null,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: value == selected
                          ? const [
                              BoxShadow(
                                color: Color(0x140F172A),
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labelOf(value),
                      style: text.labelLarge?.copyWith(
                        color: value == selected
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                        fontWeight: value == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Botón principal ancho con ícono en círculo a la izquierda y flecha a la
/// derecha ("Iniciar clase en vivo").
class ActionBarButton extends StatelessWidget {
  const ActionBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color = AppColors.primaryDark,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 2,
      shadowColor: AppColors.shadow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recuadro de aviso con ícono y fondo de color (p. ej. el reglamento).
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.child,
    this.icon = Icons.info,
    this.color = AppColors.late,
    this.background = AppColors.lateContainer,
    this.title,
  });

  final Widget child;
  final IconData icon;
  final Color color;
  final Color background;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                DefaultTextStyle.merge(
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Esquema de la distancia al salón (E3b): el círculo es el radio de la
/// clase y el pin rojo, el estudiante.
class DistanceDiagram extends StatelessWidget {
  const DistanceDiagram({
    super.key,
    required this.distance,
    required this.radius,
    required this.accuracy,
    required this.room,
  });

  final double distance;
  final int radius;
  final double accuracy;
  final String room;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final excess = (distance - radius).round();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.navigation, size: 14, color: AppColors.present),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Precisión GPS: ±${accuracy.round()} m',
                  overflow: TextOverflow.ellipsis,
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: LayoutBuilder(
              builder: (context, box) => CustomPaint(
                size: Size(box.maxWidth, 150),
                painter: _DistancePainter(),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      width: box.maxWidth / 2 - 4,
                      top: 104,
                      child: _label(
                        context,
                        '${room.isEmpty ? 'Aula' : room} ($radius m)',
                        AppColors.primaryDark,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      width: box.maxWidth / 2 - 4,
                      top: 104,
                      child: _label(
                        context,
                        'Tú · ${distance.round()} m',
                        AppColors.absent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: _legend(
                  context,
                  AppColors.present,
                  'Rango de clase: $radius m',
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: _legend(
                  context,
                  AppColors.absent,
                  'Excedente: +$excess m',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String value, Color color) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x140F172A), blurRadius: 3)],
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    ),
  );

  Widget _legend(BuildContext context, Color color, String value) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AppColors.textSecondary),
        ),
      ),
    ],
  );
}

class _DistancePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final room = Offset(size.width * 0.25, 60);
    final me = Offset(size.width * 0.75, 60);
    final area = Paint()..color = AppColors.present.withValues(alpha: 0.08);
    canvas.drawCircle(room, 52, area);
    final dash = Paint()
      ..color = AppColors.present.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const segments = 36;
    for (var i = 0; i < segments; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: room, radius: 52),
        i * 2 * math.pi / segments,
        2 * math.pi / segments,
        false,
        dash,
      );
    }
    final line = Paint()
      ..color = AppColors.absent
      ..strokeWidth = 2;
    for (var x = room.dx + 18; x < me.dx - 18; x += 10) {
      canvas.drawLine(Offset(x, room.dy), Offset(x + 5, room.dy), line);
    }
    canvas.drawCircle(room, 18, Paint()..color = AppColors.primaryDark);
    canvas.drawCircle(
      me,
      24,
      Paint()..color = AppColors.absent.withValues(alpha: 0.18),
    );
    canvas.drawCircle(me, 16, Paint()..color = AppColors.absent);
    _icon(canvas, Icons.school, room);
    _icon(canvas, Icons.person_pin_circle, me);
  }

  void _icon(Canvas canvas, IconData icon, Offset center) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_DistancePainter old) => false;
}
