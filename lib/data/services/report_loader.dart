import '../models/attendance_record.dart';
import '../models/class_session.dart';
import '../models/course.dart';
import '../models/enrollment.dart';
import '../repositories/attendance_repository.dart';
import '../repositories/course_repository.dart';
import 'attendance_stats.dart';

/// Datos del reporte de un curso (D6, D8).
class CourseReportData {
  const CourseReportData(this.course, this.enrollments, this.report);

  final Course course;
  final List<Enrollment> enrollments;
  final CourseReport report;

  StudentReportRow? rowFor(String email) {
    for (final row in report.students) {
      if (row.enrollment.email == email) return row;
    }
    return null;
  }
}

/// Lee el curso completo (clases, inscritos y todos los registros) y arma el
/// reporte. Se usa solo en pantallas que el docente abre a propósito, porque
/// lee todos los registros del curso.
Future<CourseReportData> loadCourseReport({
  required CourseRepository courses,
  required AttendanceRepository attendance,
  required String courseId,
}) async {
  final course = await courses.getCourse(courseId);
  if (course == null) throw StateError('Curso no encontrado');
  final results = await Future.wait([
    attendance.getCourseSessions(
      courseId: courseId,
      teacherId: course.teacherId,
    ),
    courses.getCourseEnrollments(courseId),
    attendance.getCourseRecords(courseId),
  ]);
  final enrollments = results[1] as List<Enrollment>;
  return CourseReportData(
    course,
    enrollments,
    buildCourseReport(
      sessions: results[0] as List<ClassSession>,
      enrollments: enrollments,
      records: results[2] as List<AttendanceRecord>,
      now: DateTime.now(),
    ),
  );
}

/// Datos de un estudiante en un curso (D7 para el docente, E5 para el
/// estudiante).
class StudentFileData {
  const StudentFileData(this.course, this.enrollment, this.stats);

  final Course course;
  final Enrollment enrollment;
  final StudentStats stats;
}

Future<StudentFileData> loadStudentFile({
  required CourseRepository courses,
  required AttendanceRepository attendance,
  required String courseId,
  required String email,
  required bool asTeacher,
}) async {
  final course = await courses.getCourse(courseId);
  final enrollment = await courses.getEnrollment(courseId, email);
  if (course == null || enrollment == null) {
    throw StateError('Inscripción no encontrada');
  }
  final sessions = asTeacher
      ? await attendance.getCourseSessions(
          courseId: courseId,
          teacherId: course.teacherId,
        )
      : await attendance.getSessionsForStudent(courseId);
  final records = await attendance.getStudentRecords(
    courseId: courseId,
    email: email,
  );
  return StudentFileData(
    course,
    enrollment,
    computeStudentStats(
      sessions: sessions,
      records: records,
      now: DateTime.now(),
      enrolledSince: enrollment.addedAt,
    ),
  );
}
