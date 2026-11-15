import 'package:cloud_firestore/cloud_firestore.dart';

/// Conteo de una clase, guardado en `sesiones.resumen` para no tener que leer
/// todos los registros al mostrar promedios.
class SessionSummary {
  const SessionSummary({
    required this.expected,
    required this.present,
    required this.late,
    required this.absent,
    required this.justified,
    required this.review,
  });

  factory SessionSummary.fromMap(Map<dynamic, dynamic> data) {
    int n(String key) => (data[key] as num?)?.toInt() ?? 0;
    return SessionSummary(
      expected: n('esperados'),
      present: n('presentes'),
      late: n('tarde'),
      absent: n('ausentes'),
      justified: n('justificados'),
      review: n('revision'),
    );
  }

  final int expected;
  final int present;
  final int late;
  final int absent;
  final int justified;
  final int review;

  /// Asistieron (presente, tarde o por revisar). Los justificados no cuentan
  /// como asistencia ni como falta.
  int get attended => present + late + review;

  Map<String, int> toMap() => {
    'esperados': expected,
    'presentes': present,
    'tarde': late,
    'ausentes': absent,
    'justificados': justified,
    'revision': review,
  };
}

enum SessionStatus {
  open('abierta'),
  closed('cerrada');

  const SessionStatus(this.value);

  final String value;

  static SessionStatus fromValue(Object? value) =>
      value == 'cerrada' ? SessionStatus.closed : SessionStatus.open;
}

/// Una clase en la que se toma asistencia. Se guarda en `sesiones/{id}`.
///
/// La ubicación y las redes WiFi las toma el teléfono del docente al iniciar.
/// El token del QR y la lista de inscritos van en la subcolección `privado`,
/// que solo lee el docente.
class ClassSession {
  const ClassSession({
    required this.id,
    required this.courseId,
    required this.teacherId,
    required this.courseName,
    required this.teacherName,
    required this.room,
    required this.number,
    required this.startedAt,
    required this.presentMinutes,
    required this.lateMinutes,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.locationAccuracy,
    required this.radiusMeters,
    required this.bssids,
    this.closedAt,
    this.summary,
  });

  factory ClassSession.fromMap(String id, Map<String, dynamic> data) {
    final location = (data['ubicacion'] as Map?) ?? const {};
    return ClassSession(
      id: id,
      courseId: (data['cursoId'] as String?) ?? '',
      teacherId: (data['docenteId'] as String?) ?? '',
      courseName: (data['cursoNombre'] as String?) ?? '',
      teacherName: (data['docenteNombre'] as String?) ?? '',
      room: (data['salon'] as String?) ?? '',
      number: (data['numero'] as num?)?.toInt() ?? 0,
      // Mientras la escritura está pendiente, el timestamp del servidor llega
      // nulo; se usa la hora local como estimación.
      startedAt: (data['inicio'] as Timestamp?)?.toDate() ?? DateTime.now(),
      presentMinutes: (data['ventanaPresenteMin'] as num?)?.toInt() ?? 10,
      lateMinutes: (data['ventanaTardeMin'] as num?)?.toInt() ?? 5,
      status: SessionStatus.fromValue(data['estado']),
      latitude: (location['lat'] as num?)?.toDouble() ?? 0,
      longitude: (location['lng'] as num?)?.toDouble() ?? 0,
      locationAccuracy: (location['precision'] as num?)?.toDouble() ?? 0,
      radiusMeters: (data['radioMetros'] as num?)?.toInt() ?? 40,
      bssids: ((data['wifi'] as List?) ?? const [])
          .whereType<String>()
          .toList(),
      closedAt: (data['cerradaEn'] as Timestamp?)?.toDate(),
      summary: data['resumen'] is Map
          ? SessionSummary.fromMap(data['resumen'] as Map)
          : null,
    );
  }

  final String id;
  final String courseId;
  final String teacherId;
  final String courseName;
  final String teacherName;
  final String room;
  final int number;
  final DateTime startedAt;
  final int presentMinutes;
  final int lateMinutes;
  final SessionStatus status;
  final double latitude;
  final double longitude;
  final double locationAccuracy;
  final int radiusMeters;

  /// Routers registrados por el docente. Vacío = no se exige WiFi.
  final List<String> bssids;
  final DateTime? closedAt;

  /// Conteo guardado al cerrar (y actualizado tras revisiones o correcciones).
  final SessionSummary? summary;

  bool get wifiRequired => bssids.isNotEmpty;

  DateTime get presentDeadline =>
      startedAt.add(Duration(minutes: presentMinutes));

  DateTime get closesAt =>
      startedAt.add(Duration(minutes: presentMinutes + lateMinutes));

  /// Terminada: cerrada o con la ventana vencida. Solo estas cuentan en las
  /// estadísticas (en una clase en curso aún no se sabe quién faltó).
  bool isFinishedAt(DateTime now) =>
      status == SessionStatus.closed || !now.isBefore(closesAt);

  /// Abierta y dentro de la ventana para marcar.
  bool isAcceptingAt(DateTime now) =>
      status == SessionStatus.open && now.isBefore(closesAt);
}
