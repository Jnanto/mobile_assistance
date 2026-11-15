import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/course.dart';
import '../../../data/services/report_export.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/teacher_courses_provider.dart';

/// Cifras del docente para el pie de la tarjeta verde de P2.
class TeacherHeroStats extends StatelessWidget {
  const TeacherHeroStats({super.key});

  @override
  Widget build(BuildContext context) {
    final courses = context.watch<TeacherCoursesProvider>();
    final text = Theme.of(context).textTheme;
    final active = courses.courses
        .where((c) => c.status == CourseStatus.active)
        .length;
    final average = courses.globalAverage;
    Widget stat(String value, String label, {Color color = Colors.white}) =>
        Expanded(
          child: Column(
            children: [
              Text(
                value,
                style: text.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: text.labelSmall?.copyWith(color: Colors.white),
              ),
            ],
          ),
        );
    return Row(
      children: [
        stat('$active', 'Asignaturas activas'),
        stat('${courses.totalStudents}', 'Estudiantes a cargo'),
        stat(
          average == null ? '—' : percent(average),
          'Asistencia global',
          color: const Color(0xFFA3F69C),
        ),
      ],
    );
  }
}

/// P2 · Tolerancia por defecto del docente para iniciar clase.
class TeacherProfileSection extends StatelessWidget {
  const TeacherProfileSection({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final text = Theme.of(context).textTheme;
    final current =
        auth.profile?.defaultPresentMinutes ??
        AppConfig.presentWindow.inMinutes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
          child: Row(
            children: [
              const Icon(Icons.tune, size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'CONFIGURACIÓN DE ASISTENCIA',
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const IconBadge(
                      icon: Icons.schedule,
                      color: AppColors.primaryDark,
                      background: AppColors.surfaceVariant,
                      size: 40,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Tolerancia para "Presente"',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StatusChip(
                      label: '$current min',
                      icon: Icons.edit_outlined,
                      foreground: AppColors.primaryDark,
                      background: AppColors.surfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Valor inicial al iniciar clase; puedes cambiarlo en cada '
                  'clase. Después hay ${AppConfig.lateWindow.inMinutes} min '
                  'para "Tarde".',
                  style: text.bodySmall?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 12),
                PillSegments<int>(
                  values: AppConfig.presentWindowOptions,
                  selected: current,
                  labelOf: (m) => '$m min',
                  onChanged: (m) async {
                    final messenger = ScaffoldMessenger.of(context);
                    final error = await auth.setDefaultPresentMinutes(m);
                    if (error != null) {
                      messenger.showSnackBar(SnackBar(content: Text(error)));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
