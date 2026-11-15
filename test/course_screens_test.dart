import 'package:asis_selva_check/features/student/screens/student_home_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/course_detail_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/course_form_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/course_students_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/teacher_home_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> fillCourseForm(WidgetTester tester, {String? code}) async {
  Finder field(String hint) => find.widgetWithText(TextFormField, hint);
  await tester.enterText(
    field('Ej. Inteligencia Artificial'),
    'Programación Móvil',
  );
  if (code != null) await tester.enterText(field('Ej. IS-502'), code);
  await tester.scrollUntilVisible(
    field('Ej. Salón 7205'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.enterText(field('Ej. Salón 7205'), 'Salón 7206');
}

void main() {
  testWidgets('D1 lista los cursos del docente con sus inscritos', (
    tester,
  ) async {
    final db = await seed();
    await pumpScreen(tester, const TeacherHomeScreen(), db: db);

    expect(find.text('¡Hola, Oscar!'), findsOneWidget);
    expect(find.text('Lógica y Algoritmos II'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('2 inscritos'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2 inscritos'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Programación Móvil'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Programación Móvil'), findsOneWidget);
    expect(find.text('Borrador'), findsOneWidget);
    expect(find.text('Nuevo curso'), findsOneWidget);
  });

  testWidgets('D3 muestra el curso y sus inscritos', (tester) async {
    final db = await seed();
    await pumpScreen(tester, const CourseDetailScreen(courseId: 'c1'), db: db);

    expect(find.text('Lógica y Algoritmos II'), findsOneWidget);
    expect(find.text('Activo · Periodo 2026-2'), findsOneWidget);
    expect(find.text('2 activos'), findsOneWidget);
    expect(find.text('Iniciar clase en vivo'), findsOneWidget);
  });

  testWidgets('D8 busca, inscribe y da de baja estudiantes', (tester) async {
    final db = await seed();
    await pumpScreen(
      tester,
      const CourseStudentsScreen(courseId: 'c1'),
      db: db,
    );

    expect(find.text('Laura Méndez'), findsOneWidget);
    expect(find.text('Carlos Ruiz'), findsOneWidget);

    // Búsqueda.
    await tester.enterText(find.byType(TextField).first, 'carlos');
    await tester.pumpAndSettle();
    expect(find.text('Laura Méndez'), findsNothing);
    expect(find.text('Carlos Ruiz'), findsOneWidget);

    // Dar de baja (D8b).
    await tester.tap(find.text('Dar de baja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retiro voluntario / Cancelación de materia'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Confirmar baja'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar baja'));
    await tester.pumpAndSettle();
    final withdrawn = await db.doc('inscripciones/c1_carlos@udla.edu.co').get();
    expect(withdrawn.data()!['estado'], 'retirado');
    expect(withdrawn.data()!['motivoBaja'], 'retiro_voluntario');
    expect(find.text('Reactivar'), findsOneWidget);

    // Inscribir a un estudiante nuevo.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar estudiante'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    final fields = find.descendant(
      of: sheet,
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Ana.Perez@udla.edu.co');
    await tester.enterText(fields.at(1), 'Ana Pérez');
    await tester.enterText(fields.at(2), '20221089201');
    await tester.ensureVisible(find.text('Confirmar inscripción'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar inscripción'));
    await tester.pumpAndSettle();

    final pre = await db.doc('preregistros/ana.perez@udla.edu.co').get();
    expect(pre.data()!['codigo'], '20221089201');
    expect(pre.data()!['creadoPor'], 'p1');
    final added = await db.doc('inscripciones/c1_ana.perez@udla.edu.co').get();
    expect(added.data()!['estado'], 'activo');
    expect(find.text('Ana Pérez'), findsOneWidget);
  });

  testWidgets('D2 crea y publica un curso', (tester) async {
    final db = FakeFirebaseFirestore();
    await pumpScreen(tester, const CourseFormScreen(), db: db);

    await fillCourseForm(tester, code: 'is-502');
    await tester.scrollUntilVisible(
      find.text('V'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('V'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Guardar curso'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Guardar curso'));
    await tester.pumpAndSettle();
    expect(find.text('¿Publicar y activar el curso?'), findsOneWidget);

    await tester.tap(find.text('Sí, publicar y activar curso'));
    await tester.pumpAndSettle();

    final courses = await db.collection('cursos').get();
    expect(courses.docs.length, 1);
    final data = courses.docs.single.data();
    expect(data['nombre'], 'Programación Móvil');
    expect(data['codigo'], 'IS-502');
    expect(data['encuentros'], [
      {
        'dia': 5,
        'inicio': 840,
        'fin': 960,
        'bloque': '',
        'salon': 'Salón 7206',
      },
    ]);
    expect(data['estado'], 'activo');
    expect(data['docenteId'], 'p1');
    expect(find.text('detalle ${courses.docs.single.id}'), findsOneWidget);
  });

  testWidgets('D2 admite hasta 2 encuentros y rechaza cruces', (tester) async {
    final db = FakeFirebaseFirestore();
    await pumpScreen(tester, const CourseFormScreen(), db: db);
    await fillCourseForm(tester);

    final scroll = find.byType(Scrollable).first;
    Future<void> reveal(Finder finder, [double delta = 200]) async {
      await tester.scrollUntilVisible(finder, delta, scrollable: scroll);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    await reveal(find.text('Agregar encuentro'), 200);
    await tester.tap(find.text('Agregar encuentro'));
    await tester.pumpAndSettle();
    expect(find.text('Encuentro 2'), findsOneWidget);
    // Con 2 encuentros ya no se pueden agregar más.
    expect(find.text('Agregar encuentro'), findsNothing);

    // El segundo encuentro el mismo día (lunes) y a la misma hora: se cruzan.
    await tester.ensureVisible(find.text('Encuentro 2'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('L').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('L').last);
    await tester.pumpAndSettle();
    await reveal(find.text('Guardar curso'), 200);
    await tester.tap(find.text('Guardar curso'));
    await tester.pumpAndSettle();
    await reveal(find.text('Dos encuentros se cruzan el mismo día.'), -100);
    expect(find.text('Dos encuentros se cruzan el mismo día.'), findsOneWidget);
    expect((await db.collection('cursos').get()).docs, isEmpty);

    // Pasa el segundo al viernes: ahora sí se guarda con dos encuentros.
    // Sube hasta el segundo encuentro (puede no estar construido aún).
    for (
      var i = 0;
      i < 20 && find.text('Encuentro 2').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(scroll, const Offset(0, 300));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('V').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('V').last);
    await tester.pumpAndSettle();
    await reveal(find.text('Guardar curso'), 200);
    await tester.tap(find.text('Guardar curso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar solo como borrador'));
    await tester.pumpAndSettle();
    final saved = (await db.collection('cursos').get()).docs.single.data();
    expect((saved['encuentros'] as List).map((m) => m['dia']), [1, 5]);
    expect(saved['estado'], 'borrador');
  });

  testWidgets('E1 muestra los cursos donde el estudiante está activo', (
    tester,
  ) async {
    final db = await seed();
    await db.doc('cursos/c3').set(courseData(name: 'Redes de Computadores'));
    await db
        .doc('inscripciones/c3_laura@udla.edu.co')
        .set(
          enrollmentData(
            'c3',
            'laura@udla.edu.co',
            'Laura Méndez',
            status: 'retirado',
          ),
        );
    await pumpScreen(
      tester,
      const StudentHomeScreen(),
      db: db,
      user: student,
      settle: false,
    );

    expect(find.text('¡Hola, Laura!'), findsOneWidget);
    expect(find.text('Lógica y Algoritmos II'), findsOneWidget);
    expect(find.text('Redes de Computadores'), findsNothing);
    // c2 es un borrador: en Firestore real las reglas impiden leerlo, así que
    // no llega a la app. La base falsa no aplica reglas.
  });
}
