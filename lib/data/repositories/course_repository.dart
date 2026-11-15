import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/course.dart';
import '../models/enrollment.dart';
import '../models/pre_registration.dart';
import '../models/roster_entry.dart';

/// El estudiante ya está activo en el curso.
class AlreadyEnrolledException implements Exception {
  const AlreadyEnrolledException();
}

/// El correo ya tiene un pre-registro con otro código estudiantil.
class CodeConflictException implements Exception {
  const CodeConflictException(this.registeredCode);

  final String registeredCode;
}

enum EnrollOutcome { added, reactivated }

/// Resultado de una importación masiva.
class ImportReport {
  int added = 0;
  int reactivated = 0;
  final List<String> skipped = [];
}

/// Acceso a `cursos`, `inscripciones` y `preregistros` en Firestore.
class CourseRepository {
  CourseRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _courses =>
      _db.collection('cursos');

  CollectionReference<Map<String, dynamic>> get _enrollments =>
      _db.collection('inscripciones');

  CollectionReference<Map<String, dynamic>> get _preRegistrations =>
      _db.collection('preregistros');

  // --- Cursos ---

  Stream<List<Course>> watchTeacherCourses(String teacherId) => _courses
      .where('docenteId', isEqualTo: teacherId)
      .snapshots()
      .map(
        (snap) => snap.docs.map((d) => Course.fromMap(d.id, d.data())).toList(),
      );

  Stream<Course?> watchCourse(String courseId) => _courses
      .doc(courseId)
      .snapshots()
      .map(
        (snap) => snap.exists ? Course.fromMap(snap.id, snap.data()!) : null,
      );

  /// Crea el curso y devuelve su id.
  Future<String> createCourse(Course course) async {
    final ref = _courses.doc();
    await ref.set({
      ...course.toMap(),
      'creadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateCourse(Course course) => _courses.doc(course.id).update({
    ...course.toMap(),
    // Campos del horario único anterior a los encuentros.
    for (final legacy in const [
      'dias',
      'horaInicio',
      'horaFin',
      'bloque',
      'salon',
    ])
      legacy: FieldValue.delete(),
    'actualizadoEn': FieldValue.serverTimestamp(),
  });

  Future<void> setCourseStatus(String courseId, CourseStatus status) =>
      _courses.doc(courseId).update({
        'estado': status.value,
        'actualizadoEn': FieldValue.serverTimestamp(),
      });

  // --- Inscripciones ---

  Stream<List<Enrollment>> watchCourseEnrollments(String courseId) =>
      _enrollments
          .where('cursoId', isEqualTo: courseId)
          .snapshots()
          .map(
            (snap) =>
                snap.docs.map((d) => Enrollment.fromMap(d.data())).toList(),
          );

  Stream<List<Enrollment>> watchStudentEnrollments(String email) => _enrollments
      .where('email', isEqualTo: email)
      .snapshots()
      .map(
        (snap) => snap.docs.map((d) => Enrollment.fromMap(d.data())).toList(),
      );

  Future<Course?> getCourse(String courseId) async {
    final snap = await _courses.doc(courseId).get();
    return snap.exists ? Course.fromMap(snap.id, snap.data()!) : null;
  }

  Future<List<Enrollment>> getCourseEnrollments(String courseId) async {
    final snap = await _enrollments.where('cursoId', isEqualTo: courseId).get();
    return snap.docs.map((d) => Enrollment.fromMap(d.data())).toList();
  }

  Future<Enrollment?> getEnrollment(String courseId, String email) async {
    final snap = await _enrollments
        .doc(Enrollment.docId(courseId, email))
        .get();
    return snap.exists ? Enrollment.fromMap(snap.data()!) : null;
  }

  Future<int> countActiveEnrollments(String courseId) async {
    final result = await _enrollments
        .where('cursoId', isEqualTo: courseId)
        .where('estado', isEqualTo: EnrollmentStatus.active.value)
        .count()
        .get();
    return result.count ?? 0;
  }

  Future<PreRegistration?> getPreRegistration(String email) async {
    final snap = await _preRegistrations.doc(email).get();
    return snap.exists ? PreRegistration.fromMap(snap.id, snap.data()!) : null;
  }

  /// Inscribe a un estudiante. Si no tiene pre-registro, lo crea para que
  /// pueda registrarse en la app con ese correo y código.
  ///
  /// Lanza [CodeConflictException] o [AlreadyEnrolledException].
  Future<EnrollOutcome> enrollStudent({
    required String courseId,
    required String teacherId,
    required RosterEntry student,
  }) async {
    final (preRegistration, existing) = await (
      getPreRegistration(student.email),
      getEnrollment(courseId, student.email),
    ).wait;
    final plan = _planEnrollment(student, preRegistration, existing);
    final batch = _db.batch();
    _addEnrollWrites(batch, plan, courseId: courseId, teacherId: teacherId);
    await batch.commit();
    return plan.outcome;
  }

  /// Escrituras por lote: cada estudiante nuevo usa dos (pre-registro e
  /// inscripción). Probado con las reglas hasta 400.
  static const _maxWritesPerBatch = 400;

  /// Lecturas de pre-registros simultáneas (las reglas no permiten
  /// consultarlos en grupo, así que se leen uno por uno).
  static const _parallelReads = 25;

  /// Inscribe varios estudiantes. Lee lo necesario en paralelo y guarda en
  /// lotes, en lugar de tres idas y vueltas al servidor por estudiante. Los
  /// que no se pueden inscribir se reportan.
  Future<ImportReport> enrollMany({
    required String courseId,
    required String teacherId,
    required List<RosterEntry> students,
    void Function(int done, int total)? onProgress,
  }) async {
    final report = ImportReport();
    final total = students.length;
    var done = 0;
    void progress(int count) => onProgress?.call(done += count, total);

    // Inscripciones que ya existen en el curso: una sola consulta.
    final enrolled = {
      for (final e in await getCourseEnrollments(courseId)) e.email: e,
    };
    final emails = {for (final s in students) s.email}.toList();
    final preRegistrations = <String, PreRegistration?>{};
    for (var i = 0; i < emails.length; i += _parallelReads) {
      final chunk = emails.skip(i).take(_parallelReads).toList();
      final found = await [for (final e in chunk) getPreRegistration(e)].wait;
      for (var j = 0; j < chunk.length; j++) {
        preRegistrations[chunk[j]] = found[j];
      }
    }

    final plans = <_EnrollPlan>[];
    final seen = <String>{};
    for (final student in students) {
      if (!seen.add(student.email)) {
        report.skipped.add('${student.email}: está repetido en la lista.');
        continue;
      }
      try {
        plans.add(
          _planEnrollment(
            student,
            preRegistrations[student.email],
            enrolled[student.email],
          ),
        );
      } on AlreadyEnrolledException {
        report.skipped.add('${student.email}: ya estaba inscrito.');
      } on CodeConflictException catch (e) {
        report.skipped.add(
          '${student.email}: ya registrado con el código ${e.registeredCode}.',
        );
      }
    }
    progress(total - plans.length);

    var start = 0;
    while (start < plans.length) {
      var writes = 0;
      var end = start;
      while (end < plans.length &&
          writes + plans[end].writes <= _maxWritesPerBatch) {
        writes += plans[end++].writes;
      }
      final chunk = plans.sublist(start, end);
      final batch = _db.batch();
      for (final plan in chunk) {
        _addEnrollWrites(batch, plan, courseId: courseId, teacherId: teacherId);
      }
      try {
        await batch.commit();
        for (final plan in chunk) {
          plan.outcome == EnrollOutcome.added
              ? report.added++
              : report.reactivated++;
        }
      } catch (_) {
        // Un lote es todo o nada: se reintenta uno por uno para guardar a
        // los demás y saber cuál falló.
        for (final plan in chunk) {
          try {
            final single = _db.batch();
            _addEnrollWrites(
              single,
              plan,
              courseId: courseId,
              teacherId: teacherId,
            );
            await single.commit();
            plan.outcome == EnrollOutcome.added
                ? report.added++
                : report.reactivated++;
          } catch (_) {
            report.skipped.add('${plan.student.email}: no se pudo inscribir.');
          }
        }
      }
      progress(chunk.length);
      start = end;
    }
    return report;
  }

  /// Decide qué hacer con un estudiante según lo que ya existe.
  ///
  /// Lanza [CodeConflictException] o [AlreadyEnrolledException].
  static _EnrollPlan _planEnrollment(
    RosterEntry student,
    PreRegistration? preRegistration,
    Enrollment? existing,
  ) {
    if (preRegistration != null &&
        preRegistration.studentCode != student.studentCode) {
      throw CodeConflictException(preRegistration.studentCode);
    }
    if (existing != null && existing.isActive) {
      throw const AlreadyEnrolledException();
    }
    return _EnrollPlan(
      student: student,
      preRegistration: preRegistration,
      reactivate: existing != null,
    );
  }

  void _addEnrollWrites(
    WriteBatch batch,
    _EnrollPlan plan, {
    required String courseId,
    required String teacherId,
  }) {
    final student = plan.student;
    final enrollmentRef = _enrollments.doc(
      Enrollment.docId(courseId, student.email),
    );
    if (plan.reactivate) {
      batch.update(enrollmentRef, {
        'estado': EnrollmentStatus.active.value,
        'motivoBaja': FieldValue.delete(),
        'observacionBaja': FieldValue.delete(),
        'bajaEn': FieldValue.delete(),
        'actualizadoEn': FieldValue.serverTimestamp(),
      });
      return;
    }
    if (plan.preRegistration == null) {
      batch.set(_preRegistrations.doc(student.email), {
        'nombre': student.name,
        'codigo': student.studentCode,
        'creadoPor': teacherId,
        'creadoEn': FieldValue.serverTimestamp(),
      });
    }
    batch.set(enrollmentRef, {
      'cursoId': courseId,
      'email': student.email,
      'nombre': plan.preRegistration?.name ?? student.name,
      'codigo': student.studentCode,
      'estado': EnrollmentStatus.active.value,
      'agregadoEn': FieldValue.serverTimestamp(),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  /// Nota definitiva (0.0 a 5.0); `null` la borra.
  Future<void> setGrade({
    required String courseId,
    required String email,
    required double? grade,
  }) => _enrollments.doc(Enrollment.docId(courseId, email)).update({
    'nota': grade ?? FieldValue.delete(),
    'actualizadoEn': FieldValue.serverTimestamp(),
  });

  Future<void> withdrawStudent({
    required String courseId,
    required String email,
    required WithdrawReason reason,
    String? note,
  }) => _enrollments.doc(Enrollment.docId(courseId, email)).update({
    'estado': EnrollmentStatus.withdrawn.value,
    'motivoBaja': reason.value,
    'observacionBaja': (note == null || note.trim().isEmpty)
        ? FieldValue.delete()
        : note.trim(),
    'bajaEn': FieldValue.serverTimestamp(),
    'actualizadoEn': FieldValue.serverTimestamp(),
  });
}

/// Lo que se hará con un estudiante al inscribirlo.
class _EnrollPlan {
  const _EnrollPlan({
    required this.student,
    required this.preRegistration,
    required this.reactivate,
  });

  final RosterEntry student;
  final PreRegistration? preRegistration;
  final bool reactivate;

  EnrollOutcome get outcome =>
      reactivate ? EnrollOutcome.reactivated : EnrollOutcome.added;

  int get writes => !reactivate && preRegistration == null ? 2 : 1;
}
