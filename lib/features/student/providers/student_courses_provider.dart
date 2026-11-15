import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/course.dart';
import '../../../data/models/enrollment.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/attendance_stats.dart';

/// Cursos en los que el estudiante está inscrito y activo.
class StudentCoursesProvider extends ChangeNotifier {
  StudentCoursesProvider(this._repo, this._attendance, this.email) {
    _enrollmentSub = _repo
        .watchStudentEnrollments(email)
        .listen(_onEnrollments, onError: _onError);
  }

  final CourseRepository _repo;
  final AttendanceRepository _attendance;
  final String email;

  StreamSubscription<List<Enrollment>>? _enrollmentSub;
  final Map<String, StreamSubscription<Course?>> _courseSubs = {};
  final Map<String, Course> _courses = {};
  final Map<String, StreamSubscription<List<ClassSession>>> _sessionSubs = {};
  final Map<String, List<ClassSession>> _openSessions = {};
  final Map<String, Enrollment> _activeEnrollments = {};
  final Map<String, StudentStats> _stats = {};
  bool _loading = true;
  String? _error;
  bool _disposed = false;

  bool get loading => _loading;
  String? get error => _error;

  /// Cursos visibles (los borradores no le llegan al estudiante).
  List<Course> get courses =>
      _courses.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  /// Conteo de asistencia del estudiante en un curso (si ya se cargó).
  StudentStats? statsFor(String courseId) => _stats[courseId];

  /// Recalcula la asistencia de cada curso (lee las clases y los registros
  /// propios).
  Future<void> refreshStats() async {
    final now = DateTime.now();
    await Future.wait([
      for (final entry in {..._activeEnrollments}.entries)
        () async {
          try {
            final results = await Future.wait([
              _attendance.getSessionsForStudent(entry.key),
              _attendance.getStudentRecords(courseId: entry.key, email: email),
            ]);
            _stats[entry.key] = computeStudentStats(
              sessions: results[0] as List<ClassSession>,
              records: results[1] as List<AttendanceRecord>,
              now: now,
              enrolledSince: entry.value.addedAt,
            );
          } catch (_) {
            // Sin conexión o sin permiso: se conserva el último valor.
          }
        }(),
    ]);
    _notify();
  }

  /// Clases abiertas donde todavía se puede marcar.
  List<ClassSession> liveSessions(DateTime now) => [
    for (final sessions in _openSessions.values)
      ...sessions.where((s) => s.isAcceptingAt(now)),
  ]..sort((a, b) => a.closesAt.compareTo(b.closesAt));

  void _onEnrollments(List<Enrollment> enrollments) {
    final activeIds = enrollments
        .where((e) => e.isActive)
        .map((e) => e.courseId)
        .toSet();
    final previous = _activeEnrollments.keys.toSet();
    _activeEnrollments
      ..clear()
      ..addEntries(
        enrollments
            .where((e) => e.isActive)
            .map((e) => MapEntry(e.courseId, e)),
      );
    _stats.removeWhere((id, _) => !activeIds.contains(id));

    for (final id in _courseSubs.keys.toList()) {
      if (!activeIds.contains(id)) {
        _courseSubs.remove(id)?.cancel();
        _courses.remove(id);
        _sessionSubs.remove(id)?.cancel();
        _openSessions.remove(id);
      }
    }
    for (final id in activeIds) {
      _courseSubs.putIfAbsent(
        id,
        () => _repo
            .watchCourse(id)
            .listen(
              (course) {
                if (course == null) {
                  _courses.remove(id);
                } else {
                  _courses[id] = course;
                }
                _notify();
              },
              // Curso en borrador o sin permiso: no se muestra.
              onError: (Object _) {
                _courses.remove(id);
                _notify();
              },
            ),
      );
    }
    for (final id in activeIds) {
      _sessionSubs.putIfAbsent(
        id,
        () => _attendance
            .watchOpenSessions(id)
            .listen(
              (sessions) {
                _openSessions[id] = sessions;
                _notify();
              },
              onError: (Object _) {
                _openSessions.remove(id);
                _notify();
              },
            ),
      );
    }
    _loading = false;
    _error = null;
    _notify();
    if (!previous.containsAll(activeIds)) refreshStats();
  }

  void _onError(Object error) {
    _loading = false;
    _error = 'No se pudieron cargar tus cursos. Revisa tu conexión.';
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _enrollmentSub?.cancel();
    for (final sub in _courseSubs.values) {
      sub.cancel();
    }
    for (final sub in _sessionSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
