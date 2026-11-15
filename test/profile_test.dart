import 'package:asis_selva_check/core/theme/app_theme.dart';
import 'package:asis_selva_check/data/models/course.dart';
import 'package:asis_selva_check/data/services/profile_services.dart';
import 'package:asis_selva_check/features/auth/providers/auth_provider.dart';
import 'package:asis_selva_check/features/profile/app_lock_gate.dart';
import 'package:asis_selva_check/features/profile/profile_controllers.dart';
import 'package:asis_selva_check/features/student/screens/mark_attendance_screen.dart';
import 'package:asis_selva_check/features/student/screens/student_home_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/student_file_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/teacher_home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'attendance_screens_test.dart' show seedWithSession;
import 'helpers.dart';

Course course({
  String id = 'c1',
  List<int> days = const [1, 3],
  int start = 840,
  String status = 'activo',
}) => Course.fromMap(id, {
  ...courseData(status: status),
  'dias': days,
  'horaInicio': start,
});

Future<void> openProfileTab(WidgetTester tester) async {
  await tester.tap(find.text('Perfil').last);
  await pumpFor(tester, const Duration(seconds: 1));
}

Future<void> scrollToText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    200,
    scrollable: find
        .descendant(
          of: find.byType(IndexedStack),
          matching: find.byType(Scrollable),
        )
        .last,
  );
  await tester.pump();
}

void main() {
  group('Avisos de clase', () {
    test('15 minutos antes de cada clase de cursos publicados', () {
      final reminders = remindersFor([
        course(days: [3, 1]),
        course(id: 'c2', status: 'borrador'),
      ]);
      expect(reminders, hasLength(2));
      expect(reminders.first.weekday, 1);
      expect(reminders.first.minuteOfDay, 840 - 15);
      expect(reminders.first.title, 'Lógica y Algoritmos II en 15 min');
      expect(reminders.map((r) => r.id).toSet(), hasLength(2));
    });

    test('una clase a las 12:05 a. m. avisa el día anterior', () {
      final r = remindersFor([
        course(days: [1], start: 5),
      ]).single;
      expect(r.weekday, 7);
      expect(r.minuteOfDay, 24 * 60 - 10);
    });

    test('activar, sincronizar y limpiar', () async {
      final service = FakeReminderService();
      final prefs = InMemoryPreferences();
      final controller = RemindersController(prefs, service);
      await controller.sync([course()]);
      expect(service.scheduled, isEmpty);

      expect(await controller.setEnabled(true), isNull);
      expect(controller.enabled, isTrue);
      expect(service.scheduled, hasLength(2));

      await controller.sync([
        course(days: [1, 3, 5]),
      ]);
      expect(service.scheduled, hasLength(3));

      await controller.clear();
      expect(service.scheduled, isEmpty);
    });

    test('sin permiso no se activa', () async {
      final controller = RemindersController(
        InMemoryPreferences(),
        FakeReminderService(granted: false),
      );
      expect(await controller.setEnabled(true), isNotNull);
      expect(controller.enabled, isFalse);
    });
  });

  group('Bloqueo con huella', () {
    testWidgets('activar exige confirmar y bloquea al abrir', (tester) async {
      final prefs = InMemoryPreferences();
      final bio = FakeBiometricService(succeeds: false);
      final controller = AppLockController(prefs, bio);
      addTearDown(controller.dispose);
      expect(await controller.setEnabled(true), isNotNull);
      expect(controller.enabled, isFalse);

      bio.succeeds = true;
      expect(await controller.setEnabled(true), isNull);
      expect(controller.enabled, isTrue);
      expect(controller.locked, isFalse);

      // Un nuevo arranque de la app empieza bloqueado.
      final next = AppLockController(prefs, bio);
      addTearDown(next.dispose);
      expect(next.locked, isTrue);
      expect(await next.unlock(), isTrue);
      expect(next.locked, isFalse);
    });

    testWidgets('la pantalla de bloqueo cubre la app hasta desbloquear', (
      tester,
    ) async {
      final prefs = InMemoryPreferences()
        ..values[PrefKeys.biometricLock] = true;
      final bio = FakeBiometricService(succeeds: false);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: FakeAuth(student),
            ),
            ChangeNotifierProvider(
              create: (_) => AppLockController(prefs, bio),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: Text('contenido')),
            builder: (context, child) => AppLockGate(child: child!),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SelvaCheck está bloqueado'), findsOneWidget);
      expect(
        find.text('No se pudo verificar. Inténtalo de nuevo.'),
        findsOneWidget,
      );

      bio.succeeds = true;
      await tester.tap(find.text('Desbloquear'));
      await tester.pumpAndSettle();
      expect(find.text('SelvaCheck está bloqueado'), findsNothing);
      expect(find.text('contenido'), findsOneWidget);
    });
  });

  testWidgets('P2 muestra cifras, guarda la tolerancia y activa avisos', (
    tester,
  ) async {
    final db = await seed();
    final auth = FakeAuth(teacher);
    final reminders = FakeReminderService();
    await pumpScreen(
      tester,
      const TeacherHomeScreen(),
      db: db,
      auth: auth,
      reminders: reminders,
      settle: false,
    );
    await openProfileTab(tester);
    expect(find.text('Asignaturas activas'), findsOneWidget);
    expect(find.text('Docente'), findsOneWidget);

    await scrollToText(tester, '15 min');
    await tester.tap(find.text('15 min'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(auth.profile!.defaultPresentMinutes, 15);

    await scrollToText(tester, 'Avisos de clase');
    await tester.tap(find.text('Avisos de clase'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    // c1 (publicado) tiene clase lunes y miércoles; c2 es borrador.
    expect(reminders.scheduled, hasLength(2));
    expect(find.textContaining('2 avisos por semana'), findsOneWidget);
  });

  testWidgets('P1 muestra el teléfono autorizado y cambia la contraseña', (
    tester,
  ) async {
    final db = await seed();
    final auth = FakeAuth(student);
    await pumpScreen(
      tester,
      const StudentHomeScreen(),
      db: db,
      user: student,
      auth: auth,
      settle: false,
    );
    await openProfileTab(tester);
    expect(find.text('20231145028'), findsOneWidget);
    await scrollToText(tester, 'Autorizado');
    expect(find.text('Autorizado'), findsOneWidget);

    await tester.ensureVisible(find.text('Cambiar contraseña'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    await tester.tap(find.text('Cambiar contraseña'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Actual123');
    await tester.enterText(fields.at(1), 'corta');
    await tester.enterText(fields.at(2), 'corta');
    await tester.ensureVisible(find.text('Guardar contraseña'));
    await tester.tap(find.text('Guardar contraseña'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(auth.passwordChanges, isEmpty);
    expect(find.text('Mínimo 8 caracteres.'), findsOneWidget);

    await tester.enterText(fields.at(1), 'NuevaClave9');
    await tester.enterText(fields.at(2), 'NuevaClave9');
    await tester.tap(find.text('Guardar contraseña'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(auth.passwordChanges.single, ('Actual123', 'NuevaClave9'));
    expect(find.text('Tu contraseña se actualizó.'), findsOneWidget);
  });

  testWidgets('E2 no deja marcar desde un teléfono que no es el vinculado', (
    tester,
  ) async {
    final db = await seedWithSession();
    await pumpScreen(
      tester,
      MarkAttendanceScreen(sessionId: 's1', scan: (_) async => 'SC1|s1|T'),
      db: db,
      user: student,
      auth: FakeAuth(student, binding: DeviceBinding.otherDevice),
      settle: false,
    );
    await tester.scrollUntilVisible(
      find.textContaining('vinculada a otro teléfono'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('vinculada a otro teléfono'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Escanear QR y registrar'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Escanear QR y registrar'));
    await pumpFor(tester, const Duration(seconds: 1));
    final record = await db.doc('asistencias/s1_laura@udla.edu.co').get();
    expect(record.exists, isFalse);
  });

  testWidgets('D7 muestra el teléfono del estudiante y lo desvincula', (
    tester,
  ) async {
    final db = await seed();
    await db.doc('usuarios/s1').set({
      'nombre': 'Laura Méndez',
      'email': 'laura@udla.edu.co',
      'rol': 'estudiante',
      'codigo': '20231145028',
      'vinculado': true,
      'dispositivo': {
        'id': 'TELEFONO_LAURA_0001',
        'modelo': 'Motorola Moto G54',
        'vinculadoEn': Timestamp.fromDate(DateTime(2026, 10, 1)),
      },
    });
    await pumpScreen(
      tester,
      const StudentFileScreen(courseId: 'c1', email: 'laura@udla.edu.co'),
      db: db,
    );
    expect(find.text('Motorola Moto G54'), findsOneWidget);
    await tester.tap(find.text('Desvincular'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desvincular').last);
    await tester.pumpAndSettle();

    final user = await db.doc('usuarios/s1').get();
    expect(user.data()!.containsKey('dispositivo'), isFalse);
    expect(find.text('Sin teléfono vinculado'), findsOneWidget);
  });

  editProfileTests();
}

void editProfileTests() {
  testWidgets('P1 edita nombre, teléfono y programa', (tester) async {
    final db = await seed();
    await db.doc('usuarios/s1').set({
      'nombre': 'Laura Méndez',
      'email': 'laura@udla.edu.co',
      'rol': 'estudiante',
      'codigo': '20231145028',
      'vinculado': true,
    });
    await pumpScreen(
      tester,
      const StudentHomeScreen(),
      db: db,
      user: student,
      settle: false,
    );
    await openProfileTab(tester);
    await scrollToText(tester, 'Editar perfil');
    await tester.tap(find.text('Editar perfil'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Laura Sofía Méndez');
    await tester.enterText(fields.at(1), 'abc');
    await tester.enterText(fields.at(2), 'Ingeniería de Sistemas');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Solo números, espacios, "+" o guiones.'), findsOneWidget);

    await tester.enterText(fields.at(1), '310 123 4567');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await pumpFor(tester, const Duration(seconds: 1));

    final user = (await db.doc('usuarios/s1').get()).data()!;
    expect(user['nombre'], 'Laura Sofía Méndez');
    expect(user['telefono'], '310 123 4567');
    expect(user['programa'], 'Ingeniería de Sistemas');
    expect(user['codigo'], '20231145028');
    expect(find.text('Tu perfil se actualizó.'), findsOneWidget);
  });

  testWidgets('P2 al cambiar el nombre lo actualiza en sus cursos', (
    tester,
  ) async {
    final db = await seed();
    await db.doc('usuarios/p1').set({
      'nombre': 'Oscar Patiño',
      'email': 'oscar@udla.edu.co',
      'rol': 'docente',
      'vinculado': true,
    });
    await pumpScreen(tester, const TeacherHomeScreen(), db: db, settle: false);
    await openProfileTab(tester);
    await scrollToText(tester, 'Editar perfil');
    await tester.tap(find.text('Editar perfil'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final fields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(fields.at(0), 'Oscar Andrés Patiño');
    await tester.enterText(fields.at(2), 'Facultad de Ingeniería');
    await tester.ensureVisible(find.text('Guardar cambios'));
    await tester.tap(find.text('Guardar cambios'));
    await pumpFor(tester, const Duration(seconds: 1));

    final user = (await db.doc('usuarios/p1').get()).data()!;
    expect(user['dependencia'], 'Facultad de Ingeniería');
    for (final id in ['c1', 'c2']) {
      final course = (await db.doc('cursos/$id').get()).data()!;
      expect(course['docenteNombre'], 'Oscar Andrés Patiño');
    }
  });
}
