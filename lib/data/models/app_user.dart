import 'package:cloud_firestore/cloud_firestore.dart';

/// Rol de un usuario. El valor se guarda en Firestore (`usuarios/{uid}.rol`).
enum UserRole {
  teacher('docente'),
  student('estudiante');

  const UserRole(this.value);

  final String value;

  /// Un rol desconocido se trata como estudiante (mínimo privilegio).
  static UserRole fromValue(Object? value) => UserRole.values.firstWhere(
    (role) => role.value == value,
    orElse: () => UserRole.student,
  );
}

/// Perfil de usuario guardado en `usuarios/{uid}`.
///
/// Los docentes se crean manualmente en la consola de Firebase con
/// `rol: "docente"` y `vinculado: true`. Los estudiantes crean su perfil al
/// registrarse con `vinculado: false` y quedan vinculados cuando existe un
/// pre-registro con su correo y código.
class AppUser {
  const AppUser({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.studentCode,
    this.linked = false,
    this.deviceId,
    this.deviceModel,
    this.deviceBoundAt,
    this.defaultPresentMinutes,
    this.phone = '',
    this.program = '',
    this.department = '',
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) => AppUser(
    uid: uid,
    name: (data['nombre'] as String?) ?? '',
    email: (data['email'] as String?) ?? '',
    role: UserRole.fromValue(data['rol']),
    studentCode: data['codigo'] as String?,
    linked: (data['vinculado'] as bool?) ?? false,
    deviceId: (data['dispositivo'] as Map?)?['id'] as String?,
    deviceModel: (data['dispositivo'] as Map?)?['modelo'] as String?,
    deviceBoundAt: ((data['dispositivo'] as Map?)?['vinculadoEn'] as Timestamp?)
        ?.toDate(),
    defaultPresentMinutes: (data['toleranciaPresenteMin'] as num?)?.toInt(),
    phone: (data['telefono'] as String?) ?? '',
    program: (data['programa'] as String?) ?? '',
    department: (data['dependencia'] as String?) ?? '',
  );

  final String uid;
  final String name;
  final String email;
  final UserRole role;
  final String? studentCode;
  final bool linked;

  /// Teléfono al que está vinculada la cuenta (estudiantes).
  final String? deviceId;
  final String? deviceModel;
  final DateTime? deviceBoundAt;

  /// Tolerancia para "Presente" que el docente usa por defecto en D4.
  final int? defaultPresentMinutes;

  /// Datos que el propio usuario puede editar en su perfil.
  final String phone;

  /// Programa académico (estudiantes).
  final String program;

  /// Facultad o dependencia (docentes).
  final String department;

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.first;
  }
}
