import 'package:asis_selva_check/data/models/roster_entry.dart';
import 'package:asis_selva_check/data/repositories/course_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

const _course = 'c1';

RosterEntry _student(int i, {String? code, String? name}) => RosterEntry(
  email: 'est$i@udla.edu.co',
  name: name ?? 'Estudiante Prueba $i',
  studentCode: code ?? '${20230000 + i}',
);

void main() {
  late FakeFirebaseFirestore db;
  late CourseRepository repository;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repository = CourseRepository(firestore: db);
    await db.doc('inscripciones/${_course}_est1@udla.edu.co').set({
      'cursoId': _course,
      'email': 'est1@udla.edu.co',
      'nombre': 'Estudiante Prueba 1',
      'codigo': '20230001',
      'estado': 'activo',
    });
    await db.doc('inscripciones/${_course}_est2@udla.edu.co').set({
      'cursoId': _course,
      'email': 'est2@udla.edu.co',
      'nombre': 'Estudiante Prueba 2',
      'codigo': '20230002',
      'estado': 'retirado',
      'motivoBaja': 'inasistencia',
    });
    // Pre-registro de otro curso: se respeta su nombre.
    await db.doc('preregistros/est3@udla.edu.co').set({
      'nombre': 'Nombre Del Preregistro',
      'codigo': '20230003',
      'creadoPor': 'p2',
    });
    await db.doc('preregistros/est4@udla.edu.co').set({
      'nombre': 'Otro Codigo',
      'codigo': '99999999',
      'creadoPor': 'p2',
    });
  });

  test('clasifica cada estudiante y guarda en lote', () async {
    final progress = <int>[];
    final report = await repository.enrollMany(
      courseId: _course,
      teacherId: 'p1',
      students: [
        _student(1),
        _student(2),
        _student(3, name: 'Nombre De La Lista'),
        _student(4),
        _student(5),
        _student(5),
      ],
      onProgress: (done, total) {
        expect(total, 6);
        progress.add(done);
      },
    );

    expect(report.added, 2);
    expect(report.reactivated, 1);
    expect(report.skipped, [
      'est1@udla.edu.co: ya estaba inscrito.',
      'est4@udla.edu.co: ya registrado con el código 99999999.',
      'est5@udla.edu.co: está repetido en la lista.',
    ]);
    expect(progress.last, 6);

    final reactivated = await db
        .doc('inscripciones/${_course}_est2@udla.edu.co')
        .get();
    expect(reactivated['estado'], 'activo');
    expect(reactivated.data()!.containsKey('motivoBaja'), isFalse);

    final existingPre = await db
        .doc('inscripciones/${_course}_est3@udla.edu.co')
        .get();
    expect(existingPre['nombre'], 'Nombre Del Preregistro');
    final preUnchanged = await db.doc('preregistros/est3@udla.edu.co').get();
    expect(preUnchanged['creadoPor'], 'p2');

    final created = await db.doc('preregistros/est5@udla.edu.co').get();
    expect(created['creadoPor'], 'p1');
    expect(created['codigo'], '20230005');
    expect(
      (await db.doc('inscripciones/${_course}_est4@udla.edu.co').get()).exists,
      isFalse,
    );
  });

  test('divide listas grandes en varios lotes', () async {
    final students = [for (var i = 100; i < 350; i++) _student(i)];
    final report = await repository.enrollMany(
      courseId: _course,
      teacherId: 'p1',
      students: students,
    );
    expect(report.added, 250);
    expect(report.skipped, isEmpty);
    final enrolled = await db
        .collection('inscripciones')
        .where('cursoId', isEqualTo: _course)
        .where('estado', isEqualTo: 'activo')
        .get();
    expect(enrolled.size, 251);
    final pre = await db.collection('preregistros').get();
    expect(pre.size, 252);
  });

  test('inscribir uno solo sigue validando código e inscripción', () async {
    await expectLater(
      repository.enrollStudent(
        courseId: _course,
        teacherId: 'p1',
        student: _student(4),
      ),
      throwsA(isA<CodeConflictException>()),
    );
    await expectLater(
      repository.enrollStudent(
        courseId: _course,
        teacherId: 'p1',
        student: _student(1),
      ),
      throwsA(isA<AlreadyEnrolledException>()),
    );
    expect(
      await repository.enrollStudent(
        courseId: _course,
        teacherId: 'p1',
        student: _student(2),
      ),
      EnrollOutcome.reactivated,
    );
    expect(
      await repository.enrollStudent(
        courseId: _course,
        teacherId: 'p1',
        student: _student(9),
      ),
      EnrollOutcome.added,
    );
    final doc = await db.doc('inscripciones/${_course}_est9@udla.edu.co').get();
    expect(doc['agregadoEn'], isA<Timestamp>());
  });
}
