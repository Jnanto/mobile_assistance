import 'package:asis_selva_check/data/models/class_session.dart';
import 'package:asis_selva_check/data/models/course.dart';
import 'package:asis_selva_check/data/services/attendance_stats.dart';
import 'package:asis_selva_check/data/services/report_export.dart';
import 'package:asis_selva_check/features/student/screens/my_attendance_tab.dart';
import 'package:asis_selva_check/features/student/screens/student_home_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/course_report_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/course_students_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/student_file_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xls;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Curso c1 con dos clases cerradas: Laura asistió a ambas; Carlos, a la
/// primera (tarde) y faltó a la segunda.
Future<FakeFirebaseFirestore> seedReport() async {
  final db = await seed();
  final day1 = DateTime(2026, 10, 5, 14);
  final day2 = DateTime(2026, 10, 7, 14);
  for (final (id, start, n) in [('s1', day1, 1), ('s2', day2, 2)]) {
    await db.doc('sesiones/$id').set({
      'cursoId': 'c1',
      'docenteId': 'p1',
      'cursoNombre': 'Lógica y Algoritmos II',
      'numero': n,
      'inicio': Timestamp.fromDate(start),
      'ventanaPresenteMin': 10,
      'ventanaTardeMin': 5,
      'estado': 'cerrada',
      'resumen': {'esperados': 2, 'ausentes': n == 2 ? 1 : 0},
    });
  }
  Future<void> mark(String sid, String email, String name, DateTime at) =>
      db.doc('asistencias/${sid}_$email').set({
        'sesionId': sid,
        'cursoId': 'c1',
        'email': email,
        'nombre': name,
        'codigo': '20231145028',
        'marcadoEn': Timestamp.fromDate(at),
        'token': 't',
        'gpsOk': true,
        'wifiOk': true,
        'revision': 'no_requerida',
      });
  await mark(
    's1',
    'laura@udla.edu.co',
    'Laura Méndez',
    day1.add(const Duration(minutes: 2)),
  );
  await mark(
    's2',
    'laura@udla.edu.co',
    'Laura Méndez',
    day2.add(const Duration(minutes: 3)),
  );
  await mark(
    's1',
    'carlos@udla.edu.co',
    'Carlos Ruiz',
    day1.add(const Duration(minutes: 12)),
  );
  return db;
}

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  testWidgets('D6 muestra promedio, gráficos y exporta PDF y Excel', (
    tester,
  ) async {
    final db = await seedReport();
    final sharer = FakeFileSharer();
    await pumpScreen(
      tester,
      const CourseReportScreen(courseId: 'c1'),
      db: db,
      sharer: sharer,
    );

    // 4 registros esperados, 1 falta → 75 %.
    expect(find.text('75 %'), findsOneWidget);
    expect(
      find.textContaining('2 clases · 2 estudiantes · 1 en riesgo'),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('Evolución por clase'));
    expect(find.text('Evolución por clase'), findsOneWidget);

    await scrollTo(tester, find.text('Carlos Ruiz'));
    expect(find.text('Superó'), findsOneWidget);

    await scrollTo(tester, find.text('Exportar PDF'));
    await tester.tap(find.text('Exportar PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Excel'));
    await tester.pumpAndSettle();
    expect(sharer.shared, hasLength(2));
    expect(sharer.shared[0].$1, endsWith('.pdf'));
    expect(sharer.shared[0].$2, pdfMime);
    expect(sharer.shared[1].$1, endsWith('.xlsx'));
    expect(sharer.shared[1].$3, greaterThan(0));
  });

  testWidgets('D7 justifica una falta y deja de estar en riesgo', (
    tester,
  ) async {
    final db = await seedReport();
    await pumpScreen(
      tester,
      const StudentFileScreen(courseId: 'c1', email: 'carlos@udla.edu.co'),
      db: db,
    );
    expect(find.text('Carlos Ruiz'), findsOneWidget);
    expect(find.text('Superó el límite'), findsOneWidget);
    expect(find.text('Sin teléfono vinculado'), findsNothing);
    await scrollTo(tester, find.text('Sin registro en el aula'));
    expect(find.text('Sin registro en el aula'), findsOneWidget);

    // La clase #2 (más reciente) es la primera del historial.
    await scrollTo(tester, find.text('Corregir').first);
    await tester.tap(find.text('Corregir').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Justificado'),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Incapacidad médica');
    await tester.ensureVisible(find.text('Guardar cambio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cambio'));
    await tester.pumpAndSettle();

    final record = await db.doc('asistencias/s2_carlos@udla.edu.co').get();
    expect(record.data()!['estadoManual'], 'justificado');
    expect(record.data()!['motivoManual'], 'Incapacidad médica');
    expect(record.data()!['corregidoPor'], 'p1');
    // La clase está cerrada: el resumen se recalcula.
    final session = await db.doc('sesiones/s2').get();
    expect(session.data()!['resumen']['justificados'], 1);
    expect(session.data()!['resumen']['ausentes'], 0);

    await scrollTo(tester, find.text('Al día'));
    expect(find.text('Al día'), findsOneWidget);
  });

  testWidgets('D8 muestra la asistencia y guarda la nota', (tester) async {
    final db = await seedReport();
    await pumpScreen(
      tester,
      const CourseStudentsScreen(courseId: 'c1'),
      db: db,
    );
    await scrollTo(tester, find.textContaining('50 % asist.'));
    expect(find.textContaining('50 % asist.'), findsOneWidget);
    await scrollTo(tester, find.text('Nota').first);
    await tester.tap(find.text('Nota').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '4,35');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final enrollments = await db
        .collection('inscripciones')
        .where('nota', isNull: false)
        .get();
    expect(enrollments.docs.single.data()['nota'], 4.4);
  });

  testWidgets('E5 muestra mi asistencia y descarga la constancia', (
    tester,
  ) async {
    final db = await seedReport();
    final sharer = FakeFileSharer();
    await pumpScreen(
      tester,
      const StudentHomeScreen(),
      db: db,
      user: student,
      sharer: sharer,
      settle: false,
    );
    await pumpFor(tester, const Duration(seconds: 2));
    // E1: porcentaje individual.
    expect(find.text('100 %'), findsOneWidget);
    expect(find.text('(2/2)'), findsOneWidget);

    await tester.tap(find.text('Mi asistencia'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Métricas del periodo 2026-2'), findsOneWidget);
    expect(find.text('100 %'), findsWidgets);
    expect(find.textContaining('Estás al día'), findsOneWidget);

    final tabScroll = find
        .descendant(
          of: find.byType(MyAttendanceTab),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Descargar constancia (PDF)'),
      200,
      scrollable: tabScroll,
    );
    // Que el botón no quede debajo de la barra de navegación.
    await tester.drag(tabScroll, const Offset(0, -200));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Descargar constancia (PDF)'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(sharer.shared.single.$1, startsWith('constancia_'));
  });

  test('el Excel exportado tiene resumen y detalle', () {
    final course = Course.fromMap('c1', courseData());
    final sessions = [
      ClassSession.fromMap('s1', {
        'numero': 1,
        'inicio': Timestamp.fromDate(DateTime(2026, 10, 5, 14)),
        'estado': 'cerrada',
      }),
    ];
    final report = buildCourseReport(
      sessions: sessions,
      enrollments: const [],
      records: const [],
      now: DateTime(2026, 11, 1),
    );
    final bytes = buildCourseReportXlsx(course: course, report: report);
    final excel = xls.Excel.decodeBytes(bytes);
    expect(excel.tables.keys, containsAll(['Resumen', 'Detalle']));
  });

  test('el PDF se genera con tildes y eñes', () async {
    final course = Course.fromMap('c1', {
      ...courseData(),
      'nombre': 'Diseño de Algoritmos — Ñandú',
    });
    final report = buildCourseReport(
      sessions: const [],
      enrollments: const [],
      records: const [],
      now: DateTime(2026, 11, 1),
    );
    final bytes = await buildCourseReportPdf(
      course: course,
      report: report,
      generatedAt: DateTime(2026, 11, 1, 10),
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
