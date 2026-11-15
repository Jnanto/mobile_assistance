import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/app_user.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/report_loader.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/student_stats_widgets.dart';
import '../widgets/manual_status_sheet.dart';

/// D7 · Ficha del estudiante: historial y corrección manual.
class StudentFileScreen extends StatefulWidget {
  const StudentFileScreen({
    super.key,
    required this.courseId,
    required this.email,
  });

  final String courseId;
  final String email;

  @override
  State<StudentFileScreen> createState() => _StudentFileScreenState();
}

class _StudentFileScreenState extends State<StudentFileScreen> {
  late Future<StudentFileData> _data = _load();

  Future<StudentFileData> _load() => loadStudentFile(
    courses: context.read<CourseRepository>(),
    attendance: context.read<AttendanceRepository>(),
    courseId: widget.courseId,
    email: widget.email,
    asTeacher: true,
  );

  Future<void> _reload() async {
    setState(() {
      _data = _load();
    });
    await _data;
  }

  Future<void> _correct(StudentFileData data, HistoryEntry entry) async {
    final saved = await showManualStatusSheet(
      context,
      session: entry.session,
      enrollment: data.enrollment,
      current: entry.status,
    );
    if (saved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cambio guardado.')));
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ficha del estudiante')),
      body: FutureBuilder<StudentFileData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'No se pudo cargar la ficha',
              message: AuthService.messageFor(snap.error!),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data!;
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                StudentStatsHeader(
                  leading: PersonAvatar(
                    name: data.enrollment.name,
                    email: data.enrollment.email,
                    size: 52,
                  ),
                  name: data.enrollment.name,
                  subtitle:
                      'Cód. ${data.enrollment.studentCode} · '
                      '${data.course.name} · ${data.course.group}',
                  stats: data.stats,
                ),
                const SizedBox(height: 12),
                _StudentDeviceCard(email: widget.email),
                const SizedBox(height: 20),
                SectionTitle(
                  'Historial de clases',
                  count: '${data.stats.total}',
                ),
                if (data.stats.history.isEmpty)
                  const Card(
                    child: EmptyState(
                      icon: Icons.event_note_outlined,
                      title: 'Sin clases todavía',
                      message: 'Aquí aparecerán las clases terminadas.',
                    ),
                  ),
                for (final entry in data.stats.history) ...[
                  HistoryTile(
                    entry: entry,
                    trailingAction: TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => _correct(data, entry),
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Corregir'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Teléfono vinculado a la cuenta del estudiante, con opción de desvincularlo
/// (si cambió de teléfono o reinstaló la app).
class _StudentDeviceCard extends StatefulWidget {
  const _StudentDeviceCard({required this.email});

  final String email;

  @override
  State<_StudentDeviceCard> createState() => _StudentDeviceCardState();
}

class _StudentDeviceCardState extends State<_StudentDeviceCard> {
  late Future<AppUser?> _user = _load();

  Future<AppUser?> _load() =>
      context.read<UserRepository>().findByEmail(widget.email);

  Future<void> _unbind(AppUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Desvincular el teléfono?'),
        content: Text(
          'La próxima vez que ${user.firstName} inicie sesión, su cuenta '
          'quedará vinculada al teléfono que use. Hazlo solo si cambió de '
          'teléfono o reinstaló la app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<UserRepository>().unbindDevice(user.uid);
      if (!mounted) return;
      setState(() {
        _user = _load();
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('Teléfono desvinculado.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.messageFor(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _user,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        final user = snap.data;
        final Widget tile;
        if (snap.hasError) {
          tile = const ListTile(
            leading: Icon(Icons.smartphone),
            title: Text('No se pudo consultar el teléfono vinculado'),
          );
        } else if (user == null) {
          tile = const ListTile(
            leading: Icon(Icons.person_off_outlined),
            title: Text('Aún no ha creado su cuenta'),
            subtitle: Text('Se registra con su correo y código.'),
          );
        } else if (user.deviceId == null) {
          tile = const ListTile(
            leading: Icon(Icons.smartphone),
            title: Text('Sin teléfono vinculado'),
            subtitle: Text('Se vinculará la próxima vez que inicie sesión.'),
          );
        } else {
          final boundAt = user.deviceBoundAt;
          tile = ListTile(
            leading: const Icon(Icons.smartphone, color: AppColors.primary),
            title: Text(user.deviceModel ?? 'Teléfono vinculado'),
            subtitle: Text(
              boundAt == null
                  ? 'Teléfono vinculado'
                  : 'Vinculado el ${ScheduleFormat.date(boundAt).toLowerCase()}',
            ),
            trailing: TextButton(
              onPressed: () => _unbind(user),
              child: const Text('Desvincular'),
            ),
          );
        }
        return Card(child: tile);
      },
    );
  }
}
