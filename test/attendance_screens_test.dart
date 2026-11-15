import 'package:asis_selva_check/core/utils/attendance_checks.dart';
import 'package:asis_selva_check/features/student/screens/mark_attendance_screen.dart';
import 'package:asis_selva_check/features/student/screens/student_home_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/live_class_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/start_class_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'helpers.dart';

Map<String, dynamic> sessionData({DateTime? start}) => {
  'cursoId': 'c1',
  'docenteId': 'p1',
  'cursoNombre': 'Lógica y Algoritmos II',
  'docenteNombre': 'Oscar Patiño',
  'salon': 'Bloque 7 · Salón 7205',
  'numero': 4,
  'inicio': Timestamp.fromDate(start ?? DateTime.now()),
  'ventanaPresenteMin': 10,
  'ventanaTardeMin': 5,
  'estado': 'abierta',
  'ubicacion': {'lat': classLat, 'lng': classLng, 'precision': 8},
  'radioMetros': 40,
  'wifi': [classBssid],
};

Map<String, dynamic> recordData(
  String email,
  String name, {
  bool gpsOk = true,
  String review = 'no_requerida',
  double? distance,
}) => {
  'sesionId': 's1',
  'cursoId': 'c1',
  'email': email,
  'nombre': name,
  'codigo': '20231145028',
  'marcadoEn': Timestamp.now(),
  'gpsOk': gpsOk,
  'wifiOk': true,
  'distanciaM': distance,
  'revision': review,
};

Future<FakeFirebaseFirestore> seedWithSession() async {
  final db = await seed();
  await db.doc('sesiones/s1').set(sessionData());
  await db.doc('sesiones/s1/privado/inscritos').set({
    'emails': ['laura@udla.edu.co', 'carlos@udla.edu.co', 'ana@udla.edu.co'],
  });
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
  testWidgets('D4 toma GPS y WiFi del docente y crea la clase', (tester) async {
    final db = await seed();
    await pumpScreen(
      tester,
      const StartClassScreen(courseId: 'c1'),
      db: db,
      wifi: FakeWifiService(nearby: ['AA:BB:CC:DD:EE:02', classBssid]),
    );

    expect(find.text('Ubicación detectada · precisión ±8 m'), findsOneWidget);
    await scrollTo(
      tester,
      find.text('Conectado al WiFi y 2 redes registradas.'),
    );
    expect(
      find.text('Conectado al WiFi y 2 redes registradas.'),
      findsOneWidget,
    );

    await scrollTo(tester, find.text('Iniciar clase ahora'));
    await tester.tap(find.text('Iniciar clase ahora'));
    await tester.pumpAndSettle();
    expect(find.text('¿Iniciar la clase ahora?'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirmar e iniciar clase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar e iniciar clase'));
    await tester.pumpAndSettle();

    final sessions = await db.collection('sesiones').get();
    expect(sessions.docs, hasLength(1));
    final session = sessions.docs.single;
    expect(session.data()['numero'], 1);
    expect(session.data()['estado'], 'abierta');
    expect(session.data()['ventanaPresenteMin'], 10);
    expect(session.data()['wifi'], [classBssid, 'aa:bb:cc:dd:ee:02']);
    final roster = await session.reference
        .collection('privado')
        .doc('inscritos')
        .get();
    expect(roster.data()!['emails'], hasLength(2));
    final qr = await session.reference.collection('privado').doc('qr').get();
    expect((qr.data()!['valor'] as String).length, 20);
    expect(find.text('clase en vivo ${session.id}'), findsOneWidget);
  });

  testWidgets('D4 no deja iniciar con ubicación simulada', (tester) async {
    final db = await seed();
    await pumpScreen(
      tester,
      const StartClassScreen(courseId: 'c1'),
      db: db,
      location: FakeLocationService(isMocked: true),
    );
    expect(find.textContaining('ubicación simulada'), findsOneWidget);
    await scrollTo(tester, find.text('Iniciar clase ahora'));
    await tester.tap(find.text('Iniciar clase ahora'));
    await tester.pumpAndSettle();
    expect(find.text('¿Iniciar la clase ahora?'), findsNothing);
  });

  testWidgets('D5 muestra el QR, rota el token y permite revisar y cerrar', (
    tester,
  ) async {
    final db = await seedWithSession();
    await db
        .doc('asistencias/s1_laura@udla.edu.co')
        .set(recordData('laura@udla.edu.co', 'Laura Méndez'));
    await db
        .doc('asistencias/s1_carlos@udla.edu.co')
        .set(
          recordData(
            'carlos@udla.edu.co',
            'Carlos Ruiz',
            gpsOk: false,
            review: 'pendiente',
            distance: 85,
          ),
        );

    await pumpScreen(
      tester,
      const LiveClassScreen(sessionId: 's1'),
      db: db,
      settle: false,
    );

    expect(find.text('2 de 3 registrados'), findsOneWidget);
    await scrollTo(tester, find.byType(QrImageView));
    expect(find.byType(QrImageView), findsOneWidget);
    final qr = await db.doc('sesiones/s1/privado/qr').get();
    final token = qr.data()!['valor'] as String;
    expect(token.length, 20);

    await scrollTo(tester, find.text('Fuera del perímetro (85 m)'));
    expect(find.text('Fuera del perímetro (85 m)'), findsOneWidget);
    await tester.tap(find.text('Aprobar'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final carlos = await db.doc('asistencias/s1_carlos@udla.edu.co').get();
    expect(carlos.data()!['revision'], 'aprobada');
    expect(carlos.data()!['revisadoPor'], 'p1');

    await scrollTo(tester, find.text('Pendientes por marcar (1)'));
    expect(find.text('Pendientes por marcar (1)'), findsOneWidget);

    await scrollTo(tester, find.text('Cerrar asistencia ahora'));
    await tester.tap(find.text('Cerrar asistencia ahora'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Cerrar asistencia'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final session = await db.doc('sesiones/s1').get();
    expect(session.data()!['estado'], 'cerrada');

    // Pasados 20 s, el token rota... pero la clase ya está cerrada: no cambia.
    await pumpFor(tester, const Duration(seconds: 21));
    final after = await db.doc('sesiones/s1/privado/qr').get();
    expect(after.data()!['valor'], token);
  });

  testWidgets('D5 rota el token cada 20 s mientras la clase está abierta', (
    tester,
  ) async {
    final db = await seedWithSession();
    await pumpScreen(
      tester,
      const LiveClassScreen(sessionId: 's1'),
      db: db,
      settle: false,
    );
    final first = (await db.doc('sesiones/s1/privado/qr').get())
        .data()!['valor'];
    await pumpFor(tester, const Duration(seconds: 21));
    final second = await db.doc('sesiones/s1/privado/qr').get();
    expect(second.data()!['valor'], isNot(first));
    expect(second.data()!['anterior'], first);
  });

  group('E2 marcar presente', () {
    Future<FakeFirebaseFirestore> pumpMark(
      WidgetTester tester, {
      String scanned = 'SC1|s1|TOKEN_DE_PRUEBA_12345',
      FakeLocationService? location,
      FakeWifiService? wifi,
    }) async {
      final db = await seedWithSession();
      await pumpScreen(
        tester,
        MarkAttendanceScreen(sessionId: 's1', scan: (_) async => scanned),
        db: db,
        user: student,
        location: location,
        wifi: wifi,
        settle: false,
      );
      return db;
    }

    testWidgets('con GPS y WiFi correctos registra sin revisión', (
      tester,
    ) async {
      final db = await pumpMark(tester);
      await scrollTo(tester, find.textContaining('Dentro del aula'));
      expect(find.textContaining('Dentro del aula'), findsOneWidget);
      await scrollTo(tester, find.text('Conectado a la red del aula.'));
      expect(find.text('Conectado a la red del aula.'), findsOneWidget);

      await scrollTo(tester, find.text('Escanear QR y registrar'));
      await tester.tap(find.text('Escanear QR y registrar'));
      await pumpFor(tester, const Duration(seconds: 1));

      final record = await db.doc('asistencias/s1_laura@udla.edu.co').get();
      expect(record.data()!['revision'], 'no_requerida');
      expect(record.data()!['token'], 'TOKEN_DE_PRUEBA_12345');
      expect(record.data()!['gpsOk'], isTrue);
      expect(record.data()!['wifiOk'], isTrue);
      expect(record.data()!['codigo'], '20231145028');
      expect(record.data()!['dispositivoId'], testDeviceId);
      expect(find.text('resultado s1'), findsOneWidget);
    });

    testWidgets('lejos del aula queda por revisar', (tester) async {
      final db = await pumpMark(
        tester,
        location: FakeLocationService(lat: classLat + 0.001),
      );
      await scrollTo(tester, find.textContaining('Estás a 111 m del salón'));
      expect(find.textContaining('Estás a 111 m del salón'), findsOneWidget);
      expect(find.text('Excedente: +71 m'), findsOneWidget);
      await scrollTo(tester, find.textContaining('"Por revisar"'));
      expect(find.textContaining('"Por revisar"'), findsOneWidget);

      await scrollTo(tester, find.text('Escanear QR y registrar'));
      await tester.tap(find.text('Escanear QR y registrar'));
      await pumpFor(tester, const Duration(seconds: 1));

      final record = await db.doc('asistencias/s1_laura@udla.edu.co').get();
      expect(record.data()!['revision'], 'pendiente');
      expect(record.data()!['gpsOk'], isFalse);
      expect(record.data()!['distanciaM'], 111);
    });

    testWidgets('sin WiFi del aula queda por revisar', (tester) async {
      final db = await pumpMark(
        tester,
        wifi: FakeWifiService(connected: 'aa:bb:cc:dd:ee:99'),
      );
      await scrollTo(tester, find.text('Tu red WiFi no es la del aula.'));
      expect(find.text('Tu red WiFi no es la del aula.'), findsOneWidget);
      await scrollTo(tester, find.text('Escanear QR y registrar'));
      await tester.tap(find.text('Escanear QR y registrar'));
      await pumpFor(tester, const Duration(seconds: 1));
      final record = await db.doc('asistencias/s1_laura@udla.edu.co').get();
      expect(record.data()!['revision'], 'pendiente');
      expect(record.data()!['wifiOk'], isFalse);
    });

    testWidgets('rechaza el QR de otra clase', (tester) async {
      final db = await pumpMark(
        tester,
        scanned: const QrPayload('otra', 'TOKEN').encode(),
      );
      await scrollTo(tester, find.text('Escanear QR y registrar'));
      await tester.tap(find.text('Escanear QR y registrar'));
      await pumpFor(tester, const Duration(seconds: 1));
      await scrollTo(tester, find.text('Ese código es de otra clase.'));
      expect(find.text('Ese código es de otra clase.'), findsOneWidget);
      final record = await db.doc('asistencias/s1_laura@udla.edu.co').get();
      expect(record.exists, isFalse);
    });
  });

  testWidgets('E1 muestra la clase en vivo con el botón para marcar', (
    tester,
  ) async {
    final db = await seedWithSession();
    await pumpScreen(
      tester,
      const StudentHomeScreen(),
      db: db,
      user: student,
      settle: false,
    );
    expect(find.text('EN VIVO · VENTANA ABIERTA'), findsOneWidget);
    expect(find.text('Marcar presente'), findsOneWidget);

    await db
        .doc('asistencias/s1_laura@udla.edu.co')
        .set(recordData('laura@udla.edu.co', 'Laura Méndez'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Registrada · Presente'), findsOneWidget);
  });
}
