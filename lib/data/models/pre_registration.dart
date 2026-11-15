/// Estudiante agregado por un docente antes de que cree su cuenta.
/// Se guarda en `preregistros/{correo en minúsculas}`.
class PreRegistration {
  const PreRegistration({
    required this.email,
    required this.name,
    required this.studentCode,
  });

  factory PreRegistration.fromMap(String email, Map<String, dynamic> data) =>
      PreRegistration(
        email: email,
        name: (data['nombre'] as String?) ?? '',
        studentCode: (data['codigo'] as String?) ?? '',
      );

  final String email;
  final String name;
  final String studentCode;
}
