import 'package:asis_selva_check/data/models/attendance_record.dart';
import 'package:asis_selva_check/data/models/class_session.dart';
import 'package:asis_selva_check/data/models/enrollment.dart';
import 'package:asis_selva_check/data/services/attendance_stats.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 11, 20, 18);

ClassSession session(String id, DateTime start, {String status = 'cerrada'}) =>
    ClassSession.fromMap(id, {
      'cursoId': 'c1',
      'numero': int.parse(id.substring(1)),
      'inicio': Timestamp.fromDate(start),
      'ventanaPresenteMin': 10,
      'ventanaTardeMin': 5,
      'estado': status,
    });

AttendanceRecord record(
  String sessionId,
  DateTime at, {
  String email = 'laura@udla.edu.co',
  String review = 'no_requerida',
  String? manual,
}) => AttendanceRecord.fromMap({
  'sesionId': sessionId,
  'cursoId': 'c1',
  'email': email,
  'marcadoEn': Timestamp.fromDate(at),
  'token': 't',
  'revision': review,
  'estadoManual': ?manual,
});

Enrollment enrollment(String email, {DateTime? addedAt}) => Enrollment.fromMap({
  'cursoId': 'c1',
  'email': email,
  'nombre': email.split('@').first,
  'codigo': '123456',
  'estado': 'activo',
  'agregadoEn': addedAt == null ? null : Timestamp.fromDate(addedAt),
});

void main() {
  // Cinco clases de lunes a viernes a las 2 p. m.
  final sessions = [
    for (var i = 1; i <= 5; i++) session('s$i', DateTime(2026, 11, 2 + i, 14)),
  ];
  DateTime at(int day, int minute) => DateTime(2026, 11, 2 + day, 14, minute);

  test('cuenta presentes, tardes, justificados y ausencias', () {
    final stats = computeStudentStats(
      sessions: sessions,
      now: now,
      records: [
        record('s1', at(1, 2)),
        record('s2', at(2, 12)), // tarde
        record('s3', at(3, 1), review: 'rechazada'), // ausente
        record('s4', at(4, 1), manual: 'justificado'),
        // s5 sin registro: ausente
      ],
    );
    expect(stats.total, 5);
    expect(stats.present, 1);
    expect(stats.late, 1);
    expect(stats.absent, 2);
    expect(stats.justified, 1);
    expect(stats.absenceRate, closeTo(0.4, 1e-9));
    expect(stats.attendanceRate, closeTo(0.6, 1e-9));
    expect(stats.risk, RiskLevel.exceeded);
    expect(stats.history.first.session.id, 's5');
    expect(stats.history.first.record, isNull);
  });

  test('por revisar no cuenta como falta', () {
    final stats = computeStudentStats(
      sessions: sessions.take(1).toList(),
      now: now,
      records: [record('s1', at(1, 2), review: 'pendiente')],
    );
    expect(stats.review, 1);
    expect(stats.absent, 0);
  });

  test('no cuenta clases anteriores a su inscripción ni clases en curso', () {
    final live = session(
      's6',
      now.subtract(const Duration(minutes: 5)),
      status: 'abierta',
    );
    final stats = computeStudentStats(
      sessions: [...sessions, live],
      now: now,
      records: const [],
      enrolledSince: DateTime(2026, 11, 5, 9),
    );
    // Solo s3, s4 y s5 (desde el 5 de noviembre); s6 aún está abierta.
    expect(stats.total, 3);
    expect(stats.absent, 3);
  });

  test('niveles de riesgo con límite del 20 %', () {
    expect(riskFor(0.10), RiskLevel.ok);
    expect(riskFor(0.15), RiskLevel.warning);
    expect(riskFor(0.20), RiskLevel.warning);
    expect(riskFor(0.21), RiskLevel.exceeded);
  });

  test('resumen de una clase con la lista de inscritos', () {
    final summary = summarizeSession(
      session: sessions.first,
      roster: ['a@udla.edu.co', 'b@udla.edu.co', 'c@udla.edu.co'],
      records: [
        record('s1', at(1, 1), email: 'a@udla.edu.co'),
        record('s1', at(1, 12), email: 'b@udla.edu.co'),
      ],
    );
    expect(summary.expected, 3);
    expect(summary.present, 1);
    expect(summary.late, 1);
    expect(summary.absent, 1);
    expect(summary.attended, 2);
  });

  test('promedio con resúmenes guardados', () {
    final withSummary = ClassSession.fromMap('s1', {
      'inicio': Timestamp.fromDate(at(1, 0)),
      'estado': 'cerrada',
      'resumen': {'esperados': 10, 'ausentes': 2},
    });
    final other = ClassSession.fromMap('s2', {
      'inicio': Timestamp.fromDate(at(2, 0)),
      'estado': 'cerrada',
      'resumen': {'esperados': 10, 'ausentes': 0},
    });
    expect(averageFromSummaries([withSummary, other]), closeTo(0.9, 1e-9));
    expect(averageFromSummaries([sessions.first]), isNull);
  });

  test('reporte del curso', () {
    final report = buildCourseReport(
      sessions: sessions,
      now: now,
      enrollments: [
        enrollment('laura@udla.edu.co'),
        enrollment('carlos@udla.edu.co'),
      ],
      records: [
        for (var i = 1; i <= 5; i++) record('s$i', at(i, 1)),
        record('s1', at(1, 1), email: 'carlos@udla.edu.co'),
      ],
    );
    expect(report.sessions, hasLength(5));
    expect(report.total, 10);
    expect(report.absent, 4);
    expect(report.average, closeTo(0.6, 1e-9));
    // Carlos (80 % de faltas) va primero y está en riesgo.
    expect(report.students.first.enrollment.email, 'carlos@udla.edu.co');
    expect(report.atRisk, hasLength(1));
    expect(report.sessionRates.first.rate, 1);
    expect(report.sessionRates.last.rate, 0.5);
  });
}
