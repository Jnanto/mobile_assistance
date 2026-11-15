import '../../core/config/app_config.dart';
import '../models/attendance_record.dart';
import '../models/class_session.dart';
import '../models/enrollment.dart';

/// Riesgo de perder la materia por inasistencia.
enum RiskLevel {
  ok,

  /// Se acerca al límite (desde [AppConfig.absenceWarningRate]).
  warning,

  /// Superó el límite de [AppConfig.maxAbsenceRate].
  exceeded,
}

RiskLevel riskFor(double absenceRate) {
  if (absenceRate > AppConfig.maxAbsenceRate) return RiskLevel.exceeded;
  if (absenceRate >= AppConfig.absenceWarningRate) return RiskLevel.warning;
  return RiskLevel.ok;
}

/// Una clase en el historial de un estudiante.
class HistoryEntry {
  const HistoryEntry(this.session, this.status, this.record);

  final ClassSession session;
  final AttendanceStatus status;

  /// `null` si no marcó (ausente).
  final AttendanceRecord? record;
}

/// Conteo de un estudiante en un curso.
///
/// Reglas: las llegadas tarde y los justificados no cuentan como
/// inasistencia; "por revisar" cuenta como asistencia hasta que el docente
/// lo rechace.
class StudentStats {
  StudentStats(this.history);

  /// Más reciente primero.
  final List<HistoryEntry> history;

  int _count(AttendanceStatus s) => history.where((h) => h.status == s).length;

  int get total => history.length;
  int get present => _count(AttendanceStatus.present);
  int get late => _count(AttendanceStatus.late);
  int get absent => _count(AttendanceStatus.absent);
  int get justified => _count(AttendanceStatus.justified);
  int get review => _count(AttendanceStatus.review);

  double get absenceRate => total == 0 ? 0 : absent / total;

  /// Porcentaje de asistencia = 1 − inasistencia.
  double get attendanceRate => 1 - absenceRate;

  RiskLevel get risk => riskFor(absenceRate);
}

/// Historial y conteo de un estudiante.
///
/// Cuenta una clase si el estudiante tiene registro en ella, o si terminó y
/// empezó después de que lo inscribieran ([enrolledSince]); en ese caso, sin
/// registro, es una ausencia.
StudentStats computeStudentStats({
  required List<ClassSession> sessions,
  required List<AttendanceRecord> records,
  required DateTime now,
  DateTime? enrolledSince,
}) {
  final bySession = {for (final r in records) r.sessionId: r};
  final history = <HistoryEntry>[];
  for (final session in sessions) {
    final record = bySession[session.id];
    if (record != null) {
      history.add(HistoryEntry(session, record.statusFor(session), record));
      continue;
    }
    final expected =
        session.isFinishedAt(now) &&
        (enrolledSince == null || !session.startedAt.isBefore(enrolledSince));
    if (expected) {
      history.add(HistoryEntry(session, AttendanceStatus.absent, null));
    }
  }
  history.sort((a, b) => b.session.startedAt.compareTo(a.session.startedAt));
  return StudentStats(history);
}

/// Conteo de una clase a partir de la lista de inscritos al iniciarla.
SessionSummary summarizeSession({
  required ClassSession session,
  required List<String> roster,
  required List<AttendanceRecord> records,
}) {
  final byEmail = {for (final r in records) r.email: r};
  final expected = {...roster, ...byEmail.keys};
  var present = 0, late = 0, absent = 0, justified = 0, review = 0;
  for (final email in expected) {
    final status =
        byEmail[email]?.statusFor(session) ?? AttendanceStatus.absent;
    switch (status) {
      case AttendanceStatus.present:
        present++;
      case AttendanceStatus.late:
        late++;
      case AttendanceStatus.absent:
        absent++;
      case AttendanceStatus.justified:
        justified++;
      case AttendanceStatus.review:
        review++;
    }
  }
  return SessionSummary(
    expected: expected.length,
    present: present,
    late: late,
    absent: absent,
    justified: justified,
    review: review,
  );
}

/// Promedio de asistencia (1 − inasistencia) usando los resúmenes guardados.
/// Devuelve `null` si aún no hay clases con resumen.
double? averageFromSummaries(Iterable<ClassSession> sessions) {
  var expected = 0, absent = 0;
  for (final s in sessions) {
    final summary = s.summary;
    if (summary == null || summary.expected == 0) continue;
    expected += summary.expected;
    absent += summary.absent;
  }
  return expected == 0 ? null : 1 - absent / expected;
}

/// Una clase dentro del reporte del curso.
class SessionRate {
  const SessionRate(this.session, this.expected, this.absent);

  final ClassSession session;
  final int expected;
  final int absent;

  double get rate => expected == 0 ? 1 : 1 - absent / expected;
}

/// Un estudiante dentro del reporte del curso.
class StudentReportRow {
  const StudentReportRow(this.enrollment, this.stats);

  final Enrollment enrollment;
  final StudentStats stats;
}

/// D6 · Reporte del curso, calculado con los estudiantes activos.
class CourseReport {
  CourseReport({
    required this.sessions,
    required this.sessionRates,
    required this.students,
  });

  /// Clases terminadas, de la más antigua a la más reciente.
  final List<ClassSession> sessions;
  final List<SessionRate> sessionRates;

  /// Ordenados de mayor a menor inasistencia.
  final List<StudentReportRow> students;

  int _sum(int Function(StudentStats s) f) =>
      students.fold(0, (sum, row) => sum + f(row.stats));

  int get total => _sum((s) => s.total);
  int get present => _sum((s) => s.present);
  int get late => _sum((s) => s.late);
  int get absent => _sum((s) => s.absent);
  int get justified => _sum((s) => s.justified);
  int get review => _sum((s) => s.review);

  /// Promedio general de asistencia; `null` si no hay datos.
  double? get average => total == 0 ? null : 1 - absent / total;

  List<StudentReportRow> get atRisk =>
      students.where((r) => r.stats.risk != RiskLevel.ok).toList();
}

CourseReport buildCourseReport({
  required List<ClassSession> sessions,
  required List<Enrollment> enrollments,
  required List<AttendanceRecord> records,
  required DateTime now,
}) {
  final finished = sessions.where((s) => s.isFinishedAt(now)).toList()
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final byEmail = <String, List<AttendanceRecord>>{};
  for (final r in records) {
    byEmail.putIfAbsent(r.email, () => []).add(r);
  }

  final rows =
      [
        for (final e in enrollments.where((e) => e.isActive))
          StudentReportRow(
            e,
            computeStudentStats(
              sessions: finished,
              records: byEmail[e.email] ?? const [],
              now: now,
              enrolledSince: e.addedAt,
            ),
          ),
      ]..sort((a, b) {
        final byRate = b.stats.absenceRate.compareTo(a.stats.absenceRate);
        return byRate != 0
            ? byRate
            : a.enrollment.name.toLowerCase().compareTo(
                b.enrollment.name.toLowerCase(),
              );
      });

  final rates = [
    for (final session in finished)
      () {
        var expected = 0, absent = 0;
        for (final row in rows) {
          for (final h in row.stats.history) {
            if (h.session.id != session.id) continue;
            expected++;
            if (h.status == AttendanceStatus.absent) absent++;
          }
        }
        return SessionRate(session, expected, absent);
      }(),
  ];

  return CourseReport(sessions: finished, sessionRates: rates, students: rows);
}
