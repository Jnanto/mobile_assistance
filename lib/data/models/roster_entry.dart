/// Datos de un estudiante que el docente agrega a un curso, a mano o desde un
/// archivo.
class RosterEntry {
  const RosterEntry({
    required this.email,
    required this.name,
    required this.studentCode,
  });

  final String email;
  final String name;
  final String studentCode;
}
