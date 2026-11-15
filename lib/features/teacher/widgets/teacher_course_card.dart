import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/course.dart';
import '../../../data/services/report_export.dart';
import '../../../shared/widgets/common_widgets.dart';

/// Tarjeta de un curso en la lista del docente (D1).
class TeacherCourseCard extends StatelessWidget {
  const TeacherCourseCard({
    super.key,
    required this.course,
    required this.enrolled,
    required this.now,
    required this.onTap,
    this.average,
  });

  final Course course;
  final int enrolled;
  final DateTime now;
  final VoidCallback onTap;

  /// Asistencia promedio del curso; `null` si aún no hay clases cerradas.
  final double? average;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = [
      course.group,
      course.code,
    ].where((s) => s.isNotEmpty).join(' · ');
    return StripeCard(
      color: AppColors.courseColor(course.colorIndex),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CourseAvatar(course: course),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CourseTodayChip(course: course, now: now),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Meta(icon: Icons.schedule, text: course.scheduleLabel),
              _Meta(
                icon: Icons.pin_drop_outlined,
                text: course.locationLabel.isEmpty
                    ? 'Sin salón'
                    : course.locationLabel,
              ),
            ],
          ),
          const SizedBox(height: 10),
          InsetPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.person, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  '$enrolled inscritos',
                  style: text.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.present,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          average == null
                              ? 'Sin clases cerradas'
                              : '${percent(average!)} asist. prom.',
                          overflow: TextOverflow.ellipsis,
                          style: text.labelSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
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

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }
}
