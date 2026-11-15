import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/attendance_checks.dart';
import '../services/attendance_stats.dart';
import '../models/attendance_record.dart';
import '../models/class_session.dart';
import '../models/course.dart';
import '../models/enrollment.dart';

/// El estudiante ya tiene una marca en esta clase.
class AlreadyMarkedException implements Exception {
  const AlreadyMarkedException();
}

/// Las reglas rechazaron la marca: QR vencido o ventana cerrada.
class MarkRejectedException implements Exception {
  const MarkRejectedException();
}

/// Datos que envía el estudiante al marcar.
class MarkRequest {
  const MarkRequest({
    required this.session,
    required this.enrollment,
    required this.uid,
    required this.token,
    required this.gps,
    required this.wifi,
    required this.deviceId,
  });

  final ClassSession session;
  final Enrollment enrollment;
  final String uid;
  final String token;
  final GpsCheck gps;
  final WifiCheck wifi;

  /// Teléfono desde el que marca; las reglas lo comparan con el vinculado.
  final String deviceId;
}

/// Acceso a `sesiones` (con su subcolección `privado`) y `asistencias`.
class AttendanceRepository {
  AttendanceRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('sesiones');

  CollectionReference<Map<String, dynamic>> get _records =>
      _db.collection('asistencias');

  DocumentReference<Map<String, dynamic>> _tokenRef(String sessionId) =>
      _sessions.doc(sessionId).collection('privado').doc('qr');

  DocumentReference<Map<String, dynamic>> _rosterRef(String sessionId) =>
      _sessions.doc(sessionId).collection('privado').doc('inscritos');

  static List<ClassSession> _toSessions(
    QuerySnapshot<Map<String, dynamic>> s,
  ) =>
      s.docs.map((d) => ClassSession.fromMap(d.id, d.data())).toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

  static List<AttendanceRecord> _toRecords(
    QuerySnapshot<Map<String, dynamic>> s,
  ) => s.docs.map((d) => AttendanceRecord.fromMap(d.data())).toList();

  // --- Sesiones ---

  Stream<ClassSession?> watchSession(String sessionId) => _sessions
      .doc(sessionId)
      .snapshots()
      .map((s) => s.exists ? ClassSession.fromMap(s.id, s.data()!) : null);

  /// Todas las clases de un curso, de la más reciente a la más antigua.
  Stream<List<ClassSession>> watchCourseSessions({
    required String courseId,
    required String teacherId,
  }) => _sessions
      .where('cursoId', isEqualTo: courseId)
      .where('docenteId', isEqualTo: teacherId)
      .snapshots()
      .map(_toSessions);

  Future<List<ClassSession>> getCourseSessions({
    required String courseId,
    required String teacherId,
  }) async => _toSessions(
    await _sessions
        .where('cursoId', isEqualTo: courseId)
        .where('docenteId', isEqualTo: teacherId)
        .get(),
  );

  /// Clases abiertas de un curso, para el estudiante.
  Stream<List<ClassSession>> watchOpenSessions(String courseId) => _sessions
      .where('cursoId', isEqualTo: courseId)
      .where('estado', isEqualTo: SessionStatus.open.value)
      .snapshots()
      .map(_toSessions);

  /// Crea la clase con su primer token y la lista de inscritos del momento.
  Future<String> startSession({
    required Course course,
    required int number,
    required int presentMinutes,
    required int lateMinutes,
    required double latitude,
    required double longitude,
    required double accuracy,
    required List<String> bssids,
    required List<String> enrolledEmails,
    required String room,
  }) async {
    final ref = _sessions.doc();
    final batch = _db.batch();
    batch.set(ref, {
      'cursoId': course.id,
      'docenteId': course.teacherId,
      'cursoNombre': course.name,
      'docenteNombre': course.teacherName,
      'salon': room,
      'numero': number,
      'inicio': FieldValue.serverTimestamp(),
      'ventanaPresenteMin': presentMinutes,
      'ventanaTardeMin': lateMinutes,
      'estado': SessionStatus.open.value,
      'ubicacion': {'lat': latitude, 'lng': longitude, 'precision': accuracy},
      'radioMetros': course.radiusMeters,
      'wifi': bssids,
    });
    batch.set(_tokenRef(ref.id), {
      'valor': QrPayload.newToken(),
      'anterior': '',
      'emitidoEn': FieldValue.serverTimestamp(),
    });
    batch.set(_rosterRef(ref.id), {'emails': enrolledEmails});
    await batch.commit();
    return ref.id;
  }

  /// Publica un token nuevo; el anterior sigue aceptándose un momento más.
  Future<void> rotateToken({
    required String sessionId,
    required String token,
    required String previous,
  }) => _tokenRef(sessionId).set({
    'valor': token,
    'anterior': previous,
    'emitidoEn': FieldValue.serverTimestamp(),
  });

  /// Correos de los estudiantes activos al iniciar la clase.
  Future<List<String>> getSessionRoster(String sessionId) async {
    final snap = await _rosterRef(sessionId).get();
    return ((snap.data()?['emails'] as List?) ?? const [])
        .whereType<String>()
        .toList();
  }

  /// Cierra la clase y guarda su resumen (presentes, ausentes, etc.).
  Future<void> closeSession(ClassSession session) async {
    final summary = await _computeSummary(session);
    await _sessions.doc(session.id).update({
      'estado': SessionStatus.closed.value,
      'cerradaEn': FieldValue.serverTimestamp(),
      'resumen': summary.toMap(),
    });
  }

  /// Recalcula el resumen después de una revisión o corrección.
  Future<void> refreshSessionSummary(ClassSession session) async {
    final summary = await _computeSummary(session);
    await _sessions.doc(session.id).update({'resumen': summary.toMap()});
  }

  Future<SessionSummary> _computeSummary(ClassSession session) async {
    final roster = await getSessionRoster(session.id);
    final records = await getSessionRecords(
      sessionId: session.id,
      courseId: session.courseId,
    );
    return summarizeSession(session: session, roster: roster, records: records);
  }

  Future<int> countCourseSessions({
    required String courseId,
    required String teacherId,
  }) async {
    final result = await _sessions
        .where('cursoId', isEqualTo: courseId)
        .where('docenteId', isEqualTo: teacherId)
        .count()
        .get();
    return result.count ?? 0;
  }

  // --- Asistencias ---

  Stream<List<AttendanceRecord>> watchSessionRecords({
    required String sessionId,
    required String courseId,
  }) => _records
      .where('sesionId', isEqualTo: sessionId)
      .where('cursoId', isEqualTo: courseId)
      .snapshots()
      .map(_toRecords);

  Future<List<AttendanceRecord>> getSessionRecords({
    required String sessionId,
    required String courseId,
  }) async => _toRecords(
    await _records
        .where('sesionId', isEqualTo: sessionId)
        .where('cursoId', isEqualTo: courseId)
        .get(),
  );

  /// Todos los registros de un curso (solo el docente).
  Future<List<AttendanceRecord>> getCourseRecords(String courseId) async =>
      _toRecords(await _records.where('cursoId', isEqualTo: courseId).get());

  /// Registros de un estudiante en un curso.
  Future<List<AttendanceRecord>> getStudentRecords({
    required String courseId,
    required String email,
  }) async => _toRecords(
    await _records
        .where('email', isEqualTo: email)
        .where('cursoId', isEqualTo: courseId)
        .get(),
  );

  /// Clases de un curso vistas por el estudiante inscrito.
  Future<List<ClassSession>> getSessionsForStudent(String courseId) async =>
      _toSessions(await _sessions.where('cursoId', isEqualTo: courseId).get());

  /// D7 / D5 · El docente asigna un estado a mano (corrección, justificación o
  /// marcado sin QR). Si el estudiante no tenía registro, se crea.
  Future<void> setManualStatus({
    required ClassSession session,
    required Enrollment enrollment,
    required AttendanceStatus status,
    required String reason,
    required String teacherId,
  }) async {
    final ref = _records.doc(
      AttendanceRecord.docId(session.id, enrollment.email),
    );
    final manual = {
      'estadoManual': manualStatusValues[status],
      'motivoManual': reason.trim(),
      'corregidoPor': teacherId,
      'corregidoEn': FieldValue.serverTimestamp(),
    };
    final existing = await ref.get();
    if (existing.exists) {
      await ref.update(manual);
    } else {
      await ref.set({
        'sesionId': session.id,
        'cursoId': session.courseId,
        'email': enrollment.email,
        'nombre': enrollment.name,
        'codigo': enrollment.studentCode,
        ...manual,
      });
    }
    if (session.status == SessionStatus.closed) {
      await refreshSessionSummary(session);
    }
  }

  Stream<AttendanceRecord?> watchMyRecord(String sessionId, String email) =>
      _records
          .doc(AttendanceRecord.docId(sessionId, email))
          .snapshots()
          .map((s) => s.exists ? AttendanceRecord.fromMap(s.data()!) : null);

  /// Registra la asistencia del estudiante. Si falla el GPS o el WiFi, la
  /// marca queda "por revisar" para que decida el docente.
  Future<void> markAttendance(MarkRequest request) async {
    final ref = _records.doc(
      AttendanceRecord.docId(request.session.id, request.enrollment.email),
    );
    try {
      final existing = await ref.get();
      if (existing.exists) throw const AlreadyMarkedException();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }

    final clean = request.gps.ok && request.wifi.ok;
    try {
      await ref.set({
        'sesionId': request.session.id,
        'cursoId': request.session.courseId,
        'email': request.enrollment.email,
        'uid': request.uid,
        'nombre': request.enrollment.name,
        'codigo': request.enrollment.studentCode,
        'marcadoEn': FieldValue.serverTimestamp(),
        'token': request.token,
        'gpsOk': request.gps.ok,
        'wifiOk': request.wifi.ok,
        'distanciaM': request.gps.distance?.roundToDouble(),
        'precisionM': request.gps.accuracy?.roundToDouble(),
        'ubicacionSimulada': request.gps.issue == GpsIssue.mocked,
        'bssid': request.wifi.bssid,
        'dispositivoId': request.deviceId,
        'revision': clean
            ? ReviewStatus.notRequired.value
            : ReviewStatus.pending.value,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') throw const MarkRejectedException();
      rethrow;
    }
  }

  /// El docente aprueba o rechaza una marca.
  Future<void> reviewRecord({
    required ClassSession session,
    required String email,
    required String teacherId,
    required bool approve,
  }) async {
    await _records.doc(AttendanceRecord.docId(session.id, email)).update({
      'revision': approve
          ? ReviewStatus.approved.value
          : ReviewStatus.rejected.value,
      'revisadoPor': teacherId,
      'revisadoEn': FieldValue.serverTimestamp(),
    });
    if (session.status == SessionStatus.closed) {
      await refreshSessionSummary(session);
    }
  }
}
