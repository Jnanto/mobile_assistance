import '../../core/config/app_config.dart';
import '../../core/utils/schedule_format.dart';

/// Estado de publicación de un curso.
enum CourseStatus {
  /// Solo lo ve el docente.
  draft('borrador'),

  /// Visible para los estudiantes inscritos y habilitado para tomar asistencia.
  active('activo'),

  /// Inhabilitado: no admite asistencias ni nuevos estudiantes.
  inactive('inactivo');

  const CourseStatus(this.value);

  final String value;

  static CourseStatus fromValue(Object? value) => CourseStatus.values
      .firstWhere((s) => s.value == value, orElse: () => CourseStatus.draft);
}

/// Un encuentro semanal del curso: día, horario y salón propios.
/// Se guarda como elemento de `cursos.encuentros`.
class CourseMeeting {
  const CourseMeeting({
    required this.day,
    required this.startMinutes,
    required this.endMinutes,
    this.block = '',
    this.room = '',
  });

  factory CourseMeeting.fromMap(Map<dynamic, dynamic> data) => CourseMeeting(
    day: (data['dia'] as num?)?.toInt() ?? 1,
    startMinutes: (data['inicio'] as num?)?.toInt() ?? 0,
    endMinutes: (data['fin'] as num?)?.toInt() ?? 0,
    block: (data['bloque'] as String?) ?? '',
    room: (data['salon'] as String?) ?? '',
  );

  /// Día con la numeración de [DateTime.weekday] (1 = lunes).
  final int day;

  /// Hora de inicio y fin en minutos desde la medianoche.
  final int startMinutes;
  final int endMinutes;

  final String block;
  final String room;

  Map<String, dynamic> toMap() => {
    'dia': day,
    'inicio': startMinutes,
    'fin': endMinutes,
    'bloque': block,
    'salon': room,
  };

  CourseMeeting copyWith({
    int? day,
    int? startMinutes,
    int? endMinutes,
    String? block,
    String? room,
  }) => CourseMeeting(
    day: day ?? this.day,
    startMinutes: startMinutes ?? this.startMinutes,
    endMinutes: endMinutes ?? this.endMinutes,
    block: block ?? this.block,
    room: room ?? this.room,
  );

  static int _minutesOf(DateTime t) => t.hour * 60 + t.minute;

  bool isOn(DateTime date) => date.weekday == day;

  bool isOngoing(DateTime now) =>
      isOn(now) &&
      _minutesOf(now) >= startMinutes &&
      _minutesOf(now) < endMinutes;

  bool isLaterToday(DateTime now) =>
      isOn(now) && _minutesOf(now) < startMinutes;

  /// "Bloque 7 · Salón 7205"
  String get locationLabel =>
      [block, room].where((s) => s.trim().isNotEmpty).join(' · ');

  /// "Lun 2:00–4:00 p. m."
  String get timeLabel =>
      '${ScheduleFormat.days([day])} '
      '${ScheduleFormat.timeRange(startMinutes, endMinutes)}';

  /// "Lun 2:00–4:00 p. m. · Salón 7205"
  String get label =>
      [timeLabel, locationLabel].where((s) => s.isNotEmpty).join(' · ');

  /// Se cruza con otro encuentro el mismo día.
  bool overlaps(CourseMeeting other) =>
      day == other.day &&
      startMinutes < other.endMinutes &&
      other.startMinutes < endMinutes;
}

/// Problema de horario de un curso, o `null` si es válido: entre 1 y
/// [AppConfig.maxMeetingsPerWeek] encuentros, con fin posterior al inicio y
/// sin cruces el mismo día.
String? validateMeetings(List<CourseMeeting> meetings) {
  if (meetings.isEmpty) return 'Agrega al menos un encuentro.';
  if (meetings.length > AppConfig.maxMeetingsPerWeek) {
    return 'Máximo ${AppConfig.maxMeetingsPerWeek} encuentros por semana.';
  }
  for (final m in meetings) {
    if (m.endMinutes <= m.startMinutes) {
      return 'En cada encuentro, la hora de fin debe ser posterior a la de '
          'inicio.';
    }
    if (m.room.trim().isEmpty) return 'Indica el salón de cada encuentro.';
  }
  for (var i = 0; i < meetings.length; i++) {
    for (var j = i + 1; j < meetings.length; j++) {
      if (meetings[i].overlaps(meetings[j])) {
        return 'Dos encuentros se cruzan el mismo día.';
      }
    }
  }
  return null;
}

/// Curso o asignatura. Se guarda en `cursos/{id}`.
class Course {
  const Course({
    required this.id,
    required this.name,
    required this.code,
    required this.group,
    required this.period,
    required this.teacherId,
    required this.teacherName,
    required this.meetings,
    required this.radiusMeters,
    required this.colorIndex,
    required this.status,
  });

  factory Course.fromMap(String id, Map<String, dynamic> data) => Course(
    id: id,
    name: (data['nombre'] as String?) ?? '',
    code: (data['codigo'] as String?) ?? '',
    group: (data['grupo'] as String?) ?? '',
    period: (data['periodo'] as String?) ?? '',
    teacherId: (data['docenteId'] as String?) ?? '',
    teacherName: (data['docenteNombre'] as String?) ?? '',
    meetings: _meetingsFrom(data),
    radiusMeters: (data['radioMetros'] as num?)?.toInt() ?? 40,
    colorIndex: (data['color'] as num?)?.toInt() ?? 0,
    status: CourseStatus.fromValue(data['estado']),
  );

  /// Lee `encuentros`; los cursos creados antes (con `dias`, `horaInicio`,
  /// `horaFin`, `bloque` y `salon` comunes) se convierten a un encuentro por
  /// día con el mismo horario y salón.
  static List<CourseMeeting> _meetingsFrom(Map<String, dynamic> data) {
    final raw = data['encuentros'];
    if (raw is List) {
      return raw.whereType<Map>().map(CourseMeeting.fromMap).toList()
        ..sort(_byDayAndTime);
    }
    final days = ((data['dias'] as List?) ?? const [])
        .whereType<num>()
        .map((d) => d.toInt())
        .toList();
    return [
      for (final day in days)
        CourseMeeting(
          day: day,
          startMinutes: (data['horaInicio'] as num?)?.toInt() ?? 0,
          endMinutes: (data['horaFin'] as num?)?.toInt() ?? 0,
          block: (data['bloque'] as String?) ?? '',
          room: (data['salon'] as String?) ?? '',
        ),
    ]..sort(_byDayAndTime);
  }

  static int _byDayAndTime(CourseMeeting a, CourseMeeting b) {
    final byDay = a.day.compareTo(b.day);
    return byDay != 0 ? byDay : a.startMinutes.compareTo(b.startMinutes);
  }

  final String id;
  final String name;
  final String code;
  final String group;
  final String period;
  final String teacherId;
  final String teacherName;

  /// Encuentros semanales, ordenados por día y hora (1 a 2).
  final List<CourseMeeting> meetings;

  final int radiusMeters;
  final int colorIndex;
  final CourseStatus status;

  /// Campos editables, en el formato de Firestore.
  Map<String, dynamic> toMap() => {
    'nombre': name,
    'codigo': code,
    'grupo': group,
    'periodo': period,
    'docenteId': teacherId,
    'docenteNombre': teacherName,
    'encuentros': [for (final m in meetings) m.toMap()],
    'radioMetros': radiusMeters,
    'color': colorIndex,
    'estado': status.value,
  };

  /// Días con clase (sin repetir), con la numeración de [DateTime.weekday].
  List<int> get days => {for (final m in meetings) m.day}.toList()..sort();

  List<CourseMeeting> meetingsOn(DateTime date) =>
      meetings.where((m) => m.isOn(date)).toList();

  bool hasClassOn(DateTime date) => meetings.any((m) => m.isOn(date));

  /// La clase de hoy está en curso según el horario.
  bool isOngoing(DateTime now) => meetings.any((m) => m.isOngoing(now));

  /// Hay clase hoy y todavía no empieza.
  bool isLaterToday(DateTime now) => meetings.any((m) => m.isLaterToday(now));

  /// El encuentro en curso o el próximo de hoy, si hay alguno.
  CourseMeeting? currentOrNextToday(DateTime now) {
    for (final m in meetings) {
      if (m.isOngoing(now)) return m;
    }
    for (final m in meetings) {
      if (m.isLaterToday(now)) return m;
    }
    return null;
  }

  /// Encuentro que corresponde a una clase iniciada en [now]: el de hoy más
  /// cercano a esa hora, o el primero del curso si hoy no hay clase.
  CourseMeeting? meetingFor(DateTime now) {
    if (meetings.isEmpty) return null;
    final today = meetingsOn(now);
    if (today.isEmpty) return meetings.first;
    final minute = now.hour * 60 + now.minute;
    int distance(CourseMeeting m) => minute < m.startMinutes
        ? m.startMinutes - minute
        : (minute > m.endMinutes ? minute - m.endMinutes : 0);
    return (today..sort((a, b) => distance(a).compareTo(distance(b)))).first;
  }

  /// "Lun 2:00–4:00 p. m. · Vie 8:00–10:00 a. m."
  String get scheduleLabel => meetings.isEmpty
      ? 'Sin horario'
      : meetings.map((m) => m.timeLabel).join(' · ');

  /// Salones sin repetir: "Bloque 7 · Salón 7205" o
  /// "Bloque 7 · Salón 7205 / Lab. 4".
  String get locationLabel {
    final rooms = <String>[];
    for (final m in meetings) {
      final label = m.locationLabel;
      if (label.isNotEmpty && !rooms.contains(label)) rooms.add(label);
    }
    return rooms.join(' / ');
  }

  /// Iniciales para el avatar del curso: "Lógica y Algoritmos II" → "LA".
  String get initials {
    final words = name
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 2 && w[0].toUpperCase() == w[0])
        .toList();
    final source = words.isEmpty ? name.split(RegExp(r'\s+')) : words;
    return source
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
  }
}
