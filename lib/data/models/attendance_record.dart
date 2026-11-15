import 'package:cloud_firestore/cloud_firestore.dart';

import 'class_session.dart';

/// Revisión del docente cuando falla el GPS o el WiFi.
enum ReviewStatus {
  notRequired('no_requerida'),
  pending('pendiente'),
  approved('aprobada'),
  rejected('rechazada');

  const ReviewStatus(this.value);

  final String value;

  static ReviewStatus fromValue(Object? value) => ReviewStatus.values
      .firstWhere((s) => s.value == value, orElse: () => ReviewStatus.pending);
}

/// Estado de asistencia que se muestra en la app.
enum AttendanceStatus { present, late, absent, justified, review }

/// Estados que el docente puede asignar a mano (corrección o marcado manual).
/// El valor se guarda en `asistencias.estadoManual`.
const manualStatusValues = {
  AttendanceStatus.present: 'presente',
  AttendanceStatus.late: 'tarde',
  AttendanceStatus.absent: 'ausente',
  AttendanceStatus.justified: 'justificado',
};

AttendanceStatus? manualStatusFromValue(Object? value) {
  for (final entry in manualStatusValues.entries) {
    if (entry.value == value) return entry.key;
  }
  return null;
}

/// Marca de asistencia de un estudiante en una clase.
/// Se guarda en `asistencias/{sesionId}_{correo}`.
class AttendanceRecord {
  const AttendanceRecord({
    required this.sessionId,
    required this.courseId,
    required this.email,
    required this.name,
    required this.studentCode,
    required this.markedAt,
    required this.gpsOk,
    required this.wifiOk,
    required this.review,
    this.distanceMeters,
    this.accuracyMeters,
    this.mockedLocation = false,
    this.bssid,
    this.manualStatus,
    this.manualReason,
    this.correctedAt,
    this.selfMarked = true,
  });

  factory AttendanceRecord.fromMap(Map<String, dynamic> data) =>
      AttendanceRecord(
        sessionId: (data['sesionId'] as String?) ?? '',
        courseId: (data['cursoId'] as String?) ?? '',
        email: (data['email'] as String?) ?? '',
        name: (data['nombre'] as String?) ?? '',
        studentCode: (data['codigo'] as String?) ?? '',
        markedAt: (data['marcadoEn'] as Timestamp?)?.toDate(),
        gpsOk: (data['gpsOk'] as bool?) ?? false,
        wifiOk: (data['wifiOk'] as bool?) ?? false,
        // Un registro creado a mano por el docente no tiene revisión.
        review: data['revision'] == null
            ? ReviewStatus.notRequired
            : ReviewStatus.fromValue(data['revision']),
        distanceMeters: (data['distanciaM'] as num?)?.toDouble(),
        accuracyMeters: (data['precisionM'] as num?)?.toDouble(),
        mockedLocation: (data['ubicacionSimulada'] as bool?) ?? false,
        bssid: data['bssid'] as String?,
        manualStatus: manualStatusFromValue(data['estadoManual']),
        manualReason: data['motivoManual'] as String?,
        correctedAt: (data['corregidoEn'] as Timestamp?)?.toDate(),
        selfMarked: data['token'] != null,
      );

  final String sessionId;
  final String courseId;
  final String email;
  final String name;
  final String studentCode;

  /// Hora del servidor; `null` mientras la escritura está pendiente.
  final DateTime? markedAt;
  final bool gpsOk;
  final bool wifiOk;
  final ReviewStatus review;
  final double? distanceMeters;
  final double? accuracyMeters;
  final bool mockedLocation;
  final String? bssid;

  /// Estado asignado por el docente; si existe, manda sobre todo lo demás.
  final AttendanceStatus? manualStatus;
  final String? manualReason;
  final DateTime? correctedAt;

  /// `true` si lo marcó el estudiante con el QR; `false` si lo creó el docente.
  final bool selfMarked;

  static String docId(String sessionId, String email) => '${sessionId}_$email';

  String get id => docId(sessionId, email);

  /// Presente o Tarde según la hora de marcado, sin considerar la revisión.
  AttendanceStatus timingStatus(ClassSession session) {
    final at = markedAt ?? DateTime.now();
    return at.isAfter(session.presentDeadline)
        ? AttendanceStatus.late
        : AttendanceStatus.present;
  }

  /// Estado final: la corrección manual manda; una marca rechazada cuenta
  /// como ausencia.
  AttendanceStatus statusFor(ClassSession session) =>
      manualStatus ??
      switch (review) {
        ReviewStatus.rejected => AttendanceStatus.absent,
        ReviewStatus.pending => AttendanceStatus.review,
        _ => timingStatus(session),
      };

  /// Motivos por los que quedó en revisión, para mostrarlos al docente.
  List<String> get reviewReasons => [
    if (mockedLocation) 'Ubicación simulada',
    if (!gpsOk && !mockedLocation)
      distanceMeters == null
          ? 'Sin ubicación GPS'
          : 'Fuera del perímetro (${distanceMeters!.round()} m)',
    if (!wifiOk) 'No conectado al WiFi del aula',
  ];
}
