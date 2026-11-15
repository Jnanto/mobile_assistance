import 'package:cloud_firestore/cloud_firestore.dart';

/// Estado de un estudiante dentro de un curso.
enum EnrollmentStatus {
  active('activo'),
  withdrawn('retirado');

  const EnrollmentStatus(this.value);

  final String value;

  static EnrollmentStatus fromValue(Object? value) =>
      EnrollmentStatus.values.firstWhere(
        (s) => s.value == value,
        orElse: () => EnrollmentStatus.active,
      );
}

/// Motivo de baja de un estudiante (D8b).
enum WithdrawReason {
  absences(
    'inasistencia',
    'Inasistencia reiterada',
    'Superó el límite de faltas',
  ),
  voluntary(
    'retiro_voluntario',
    'Retiro voluntario / Cancelación de materia',
    'Solicitado por el estudiante',
  ),
  registrationError(
    'error_registro',
    'Error de registro',
    'El estudiante no pertenece a este curso',
  );

  const WithdrawReason(this.value, this.label, this.description);

  final String value;
  final String label;
  final String description;

  static WithdrawReason? fromValue(Object? value) {
    for (final reason in WithdrawReason.values) {
      if (reason.value == value) return reason;
    }
    return null;
  }
}

/// Estudiante inscrito en un curso. Se guarda en
/// `inscripciones/{cursoId}_{correo}`; el correo identifica al estudiante
/// aunque aún no haya creado su cuenta.
class Enrollment {
  const Enrollment({
    required this.courseId,
    required this.email,
    required this.name,
    required this.studentCode,
    required this.status,
    this.withdrawReason,
    this.withdrawNote,
    this.addedAt,
    this.grade,
  });

  factory Enrollment.fromMap(Map<String, dynamic> data) => Enrollment(
    courseId: (data['cursoId'] as String?) ?? '',
    email: (data['email'] as String?) ?? '',
    name: (data['nombre'] as String?) ?? '',
    studentCode: (data['codigo'] as String?) ?? '',
    status: EnrollmentStatus.fromValue(data['estado']),
    withdrawReason: WithdrawReason.fromValue(data['motivoBaja']),
    withdrawNote: data['observacionBaja'] as String?,
    addedAt: (data['agregadoEn'] as Timestamp?)?.toDate(),
    grade: (data['nota'] as num?)?.toDouble(),
  );

  final String courseId;
  final String email;
  final String name;
  final String studentCode;
  final EnrollmentStatus status;
  final WithdrawReason? withdrawReason;
  final String? withdrawNote;

  /// Desde cuándo está inscrito: las clases anteriores no le cuentan.
  final DateTime? addedAt;

  /// Nota definitiva (0.0 a 5.0) que ingresa el docente a mano.
  final double? grade;

  static String docId(String courseId, String email) => '${courseId}_$email';

  String get id => docId(courseId, email);

  bool get isActive => status == EnrollmentStatus.active;

  String get initials => name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();
}
