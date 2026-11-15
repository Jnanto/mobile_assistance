import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/attendance_record.dart';
import '../../data/models/course.dart';
import '../../features/profile/profile_photos.dart';

/// Etiqueta en forma de píldora para estados.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.dot = false,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  /// Punto de color antes del texto (estados "en vivo" o "hoy").
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip con el estado de un curso para hoy.
class CourseTodayChip extends StatelessWidget {
  const CourseTodayChip({super.key, required this.course, required this.now});

  final Course course;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    switch (course.status) {
      case CourseStatus.draft:
        return const StatusChip(
          label: 'Borrador',
          icon: Icons.edit_note,
          foreground: AppColors.textSecondary,
          background: AppColors.surfaceVariant,
        );
      case CourseStatus.inactive:
        return const StatusChip(
          label: 'Inhabilitado',
          icon: Icons.block,
          foreground: AppColors.absent,
          background: AppColors.absentContainer,
        );
      case CourseStatus.active:
        if (course.isOngoing(now)) {
          return const StatusChip(
            label: 'Clase ahora',
            dot: true,
            foreground: AppColors.present,
            background: AppColors.presentContainer,
          );
        }
        if (course.hasClassOn(now)) {
          return const StatusChip(
            label: 'Clase hoy',
            dot: true,
            foreground: AppColors.present,
            background: AppColors.presentContainer,
          );
        }
        return const StatusChip(
          label: 'Sin clase hoy',
          foreground: AppColors.textMuted,
          background: AppColors.surfaceContainerHighest,
        );
    }
  }
}

/// Avatar circular con las iniciales del curso en su color.
class CourseAvatar extends StatelessWidget {
  const CourseAvatar({super.key, required this.course, this.size = 40});

  final Course course;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.courseColor(course.colorIndex);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Text(
        course.initials,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Fila de ícono + texto para datos como horario o salón.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Tarjeta pequeña con una cifra y su etiqueta.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color = AppColors.primary,
  });

  final String value;
  final String label;
  final IconData? icon;

  /// Color de la cifra.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(height: 4),
            ],
            Text(value, style: text.headlineSmall?.copyWith(color: color)),
            const SizedBox(height: 2),
            Text(
              label,
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Mensaje centrado para listas vacías.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.outlineVariant),
          const SizedBox(height: 12),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            message,
            style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Título de sección con un texto opcional a la derecha y, opcionalmente,
/// una cantidad en píldora junto al título.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.count});

  final String title;
  final String? trailing;

  /// Texto de la píldora junto al título (p. ej. "2 cursos").
  final String? count;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count!,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            // Junto a una píldora el texto es corto (una acción o el
            // periodo): toma su ancho y el título se ajusta.
            if (count != null)
              Text(
                trailing!,
                style: text.labelMedium?.copyWith(color: AppColors.primary),
              )
            else
              Flexible(
                child: Text(
                  trailing!,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Círculo verde con el ícono de persona, como en la barra superior de los
/// mockups. Abre el perfil.
class ProfileBadgeButton extends StatelessWidget {
  const ProfileBadgeButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: IconButton(
        tooltip: 'Perfil',
        onPressed: onPressed,
        icon: Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            color: AppColors.primaryDark,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}

/// Marca de SelvaCheck para la barra superior.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.eco_rounded,
              size: 20,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto de perfil de [email] o, si no tiene, sus iniciales.
class PhotoOrInitials extends StatelessWidget {
  const PhotoOrInitials({
    super.key,
    required this.name,
    this.email,
    this.size = 40,
    this.background = AppColors.primaryContainer,
    this.foreground = AppColors.primaryDark,
  });

  final String name;
  final String? email;
  final double size;
  final Color background;
  final Color foreground;

  String get _initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final email = this.email;
    final photo = email == null
        ? null
        : context.select<PhotoCache, Uint8List?>((c) => c.photoOf(email));
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: photo != null
          ? Image.memory(
              photo,
              width: size,
              height: size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            )
          : Text(
              _initials,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.36,
              ),
            ),
    );
  }
}

/// Avatar de una persona (foto o iniciales) con un punto verde.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.email,
    this.size = 48,
  });

  final String name;
  final String? email;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: PhotoOrInitials(name: name, email: email, size: size),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.29,
              height: size * 0.29,
              decoration: BoxDecoration(
                color: AppColors.present,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Franja gris redondeada dentro de una tarjeta (datos secundarios).
class InsetPanel extends StatelessWidget {
  const InsetPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// Tarjeta con franja de color a la izquierda (lista de cursos).
class StripeCard extends StatelessWidget {
  const StripeCard({
    super.key,
    required this.color,
    required this.child,
    this.onTap,
  });

  final Color color;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: color),
              Expanded(
                child: Padding(padding: const EdgeInsets.all(14), child: child),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text('$feature estará disponible en la próxima fase.')),
    );
}

/// Etiqueta, ícono y colores de cada estado de asistencia.
({String label, IconData icon, Color fg, Color bg}) attendanceStyle(
  AttendanceStatus status,
) => switch (status) {
  AttendanceStatus.present => (
    label: 'Presente',
    icon: Icons.check_circle_outline,
    fg: AppColors.present,
    bg: AppColors.presentContainer,
  ),
  AttendanceStatus.late => (
    label: 'Tarde',
    icon: Icons.schedule,
    fg: AppColors.late,
    bg: AppColors.lateContainer,
  ),
  AttendanceStatus.absent => (
    label: 'Ausente',
    icon: Icons.cancel_outlined,
    fg: AppColors.absent,
    bg: AppColors.absentContainer,
  ),
  AttendanceStatus.justified => (
    label: 'Justificado',
    icon: Icons.description_outlined,
    fg: AppColors.justified,
    bg: AppColors.justifiedContainer,
  ),
  AttendanceStatus.review => (
    label: 'Por revisar',
    icon: Icons.hourglass_bottom,
    fg: AppColors.review,
    bg: AppColors.reviewContainer,
  ),
};

class AttendanceChip extends StatelessWidget {
  const AttendanceChip({super.key, required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final style = attendanceStyle(status);
    return StatusChip(
      label: style.label,
      icon: style.icon,
      foreground: style.fg,
      background: style.bg,
    );
  }
}
