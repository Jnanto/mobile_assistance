import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/course.dart';
import '../../../data/models/class_session.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';

/// Cursos del docente en tiempo real, con el número de inscritos activos.
class TeacherCoursesProvider extends ChangeNotifier {
  TeacherCoursesProvider(this._repo, this._attendance, this.teacherId) {
    _sub = _repo
        .watchTeacherCourses(teacherId)
        .listen(_onCourses, onError: _onError);
  }

  final CourseRepository _repo;
  final AttendanceRepository _attendance;
  final String teacherId;
  StreamSubscription<List<Course>>? _sub;
  bool _disposed = false;

  List<Course> _courses = [];
  final Map<String, int> _enrolledCounts = {};
  final Map<String, List<ClassSession>> _sessions = {};
  bool _loading = true;
  String? _error;

  List<Course> get courses => _courses;
  bool get loading => _loading;
  String? get error => _error;

  int enrolledCount(String courseId) => _enrolledCounts[courseId] ?? 0;

  /// Asistencia global de los cursos publicados (según los resúmenes de las
  /// clases cerradas); `null` si aún no hay datos.
  double? get globalAverage => averageFromSummaries([
    for (final c in _courses.where((c) => c.status == CourseStatus.active))
      ...?_sessions[c.id],
  ]);

  /// Asistencia promedio de un curso según sus clases cerradas.
  double? courseAverage(String courseId) =>
      averageFromSummaries(_sessions[courseId] ?? const []);

  /// Estudiantes activos en cursos publicados.
  int get totalStudents => _courses
      .where((c) => c.status == CourseStatus.active)
      .fold(0, (sum, c) => sum + enrolledCount(c.id));

  List<Course> classesToday(DateTime now) => _courses
      .where((c) => c.status == CourseStatus.active && c.hasClassOn(now))
      .toList();

  /// La clase en curso o la próxima de hoy, si hay alguna.
  Course? nextClassToday(DateTime now) {
    final pending =
        classesToday(now)
            .where((c) => c.isOngoing(now) || c.isLaterToday(now))
            .toList()
          ..sort(
            (a, b) => a
                .currentOrNextToday(now)!
                .startMinutes
                .compareTo(b.currentOrNextToday(now)!.startMinutes),
          );
    return pending.isEmpty ? null : pending.first;
  }

  void _onCourses(List<Course> courses) {
    const order = {
      CourseStatus.active: 0,
      CourseStatus.draft: 1,
      CourseStatus.inactive: 2,
    };
    _courses = [...courses]
      ..sort((a, b) {
        final byStatus = order[a.status]!.compareTo(order[b.status]!);
        return byStatus != 0
            ? byStatus
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    _loading = false;
    _error = null;
    _notify();
    refreshCounts();
  }

  void _onError(Object error) {
    _loading = false;
    _error = 'No se pudieron cargar tus cursos. Revisa tu conexión.';
    _notify();
  }

  /// Cuenta inscritos y trae las clases de todos los cursos a la vez (no
  /// curso por curso: cada consulta es una ida y vuelta al servidor).
  Future<void> refreshCounts() async {
    await Future.wait([
      for (final course in _courses) _refreshCourse(course.id),
    ]);
    _notify();
  }

  Future<void> _refreshCourse(String courseId) async {
    try {
      final (count, sessions) = await (
        _repo.countActiveEnrollments(courseId),
        _attendance.getCourseSessions(courseId: courseId, teacherId: teacherId),
      ).wait;
      _enrolledCounts[courseId] = count;
      _sessions[courseId] = sessions;
    } catch (_) {
      // Si falla el conteo se muestra el último valor conocido.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
