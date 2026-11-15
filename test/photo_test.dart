import 'dart:convert';
import 'dart:typed_data';

import 'package:asis_selva_check/data/repositories/photo_repository.dart';
import 'package:asis_selva_check/features/student/screens/student_home_screen.dart';
import 'package:asis_selva_check/features/teacher/screens/course_students_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('el repositorio guarda en base64 y rechaza fotos pesadas', () async {
    final db = FakeFirebaseFirestore();
    final repo = PhotoRepository(firestore: db);
    await repo.save('Laura@udla.edu.co', FakePhotoPicker.tinyJpeg);
    final doc = await db.doc('fotos/laura@udla.edu.co').get();
    expect(
      base64Decode(doc.data()!['imagen'] as String),
      FakePhotoPicker.tinyJpeg,
    );
    expect(await repo.get('laura@udla.edu.co'), FakePhotoPicker.tinyJpeg);
    expect(
      () => repo.save(
        'laura@udla.edu.co',
        Uint8List(PhotoRepository.maxBytes + 1),
      ),
      throwsArgumentError,
    );
    await repo.delete('laura@udla.edu.co');
    expect(await repo.get('laura@udla.edu.co'), isNull);
  });

  testWidgets('P1 pone y quita la foto de perfil', (tester) async {
    final db = await seed();
    final picker = FakePhotoPicker();
    await pumpScreen(
      tester,
      const StudentHomeScreen(),
      db: db,
      user: student,
      picker: picker,
      settle: false,
    );
    await tester.tap(find.text('Perfil').last);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Sin foto: se muestran tus iniciales'), findsOneWidget);

    await tester.tap(find.text('Foto de perfil'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Elegir de la galería'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(picker.requests, [false]);
    final saved = await db.doc('fotos/laura@udla.edu.co').get();
    expect(saved.exists, isTrue);
    expect(find.text('Foto actualizada.'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Cámbiala o quítala cuando quieras'), findsOneWidget);

    await tester.tap(find.text('Foto de perfil'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Quitar foto'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect((await db.doc('fotos/laura@udla.edu.co').get()).exists, isFalse);
    expect(find.text('Sin foto: se muestran tus iniciales'), findsOneWidget);
  });

  testWidgets('D8 muestra la foto del estudiante que la tiene', (tester) async {
    final db = await seed();
    await PhotoRepository(firestore: db)
        .save('laura@udla.edu.co', FakePhotoPicker.tinyJpeg);
    await pumpScreen(
      tester,
      const CourseStudentsScreen(courseId: 'c1'),
      db: db,
      settle: false,
    );
    await pumpFor(tester, const Duration(seconds: 1));
    // Laura tiene foto; Carlos, sus iniciales.
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('CR'), findsOneWidget);
  });
}
