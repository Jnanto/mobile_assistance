/// Formato de horarios y periodos académicos.
abstract final class ScheduleFormat {
  /// Letras de los días para los selectores (1 = lunes … 6 = sábado).
  static const Map<int, String> dayLetters = {
    1: 'L',
    2: 'M',
    3: 'X',
    4: 'J',
    5: 'V',
    6: 'S',
  };

  static const Map<int, String> _dayShort = {
    1: 'Lun',
    2: 'Mar',
    3: 'Mié',
    4: 'Jue',
    5: 'Vie',
    6: 'Sáb',
    7: 'Dom',
  };

  /// `[1, 3]` → "Lun y Mié"; `[1, 3, 5]` → "Lun, Mié y Vie".
  static String days(List<int> days) {
    final names = ([
      ...days,
    ]..sort()).map((d) => _dayShort[d]).whereType<String>().toList();
    if (names.isEmpty) return 'Sin días';
    if (names.length == 1) return names.first;
    return '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
  }

  /// `840` → "2:00 p. m."
  static String time(int minutes) {
    final h24 = (minutes ~/ 60) % 24;
    final m = (minutes % 60).toString().padLeft(2, '0');
    final suffix = h24 < 12 ? 'a. m.' : 'p. m.';
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:$m $suffix';
  }

  /// `840, 960` → "2:00–4:00 p. m."; si cambia de mañana a tarde muestra
  /// ambos sufijos.
  static String timeRange(int start, int end) {
    final startText = time(start);
    final endText = time(end);
    final sameHalf = (start ~/ 60 < 12) == (end ~/ 60 < 12);
    if (sameHalf) {
      final startNoSuffix = startText.substring(0, startText.indexOf(' '));
      return '$startNoSuffix–$endText';
    }
    return '$startText – $endText';
  }

  static const _weekdays = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  static const _months = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  /// "Lunes, 24 de febrero"
  static String date(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${d.day} de ${_months[d.month - 1]}';

  /// "Lunes"
  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  /// "feb"
  static String monthShort(DateTime d) => _months[d.month - 1].substring(0, 3);

  /// "24 feb"
  static String shortDate(DateTime d) =>
      '${d.day} ${_months[d.month - 1].substring(0, 3)}';

  /// Hora de un [DateTime]: "2:04 p. m."
  static String clock(DateTime d) => time(d.hour * 60 + d.minute);

  /// Periodo académico actual y los dos anteriores: "2026-2", "2026-1", "2025-2".
  static List<String> recentPeriods(DateTime now) {
    var year = now.year;
    var half = now.month <= 6 ? 1 : 2;
    final periods = <String>[];
    for (var i = 0; i < 3; i++) {
      periods.add('$year-$half');
      if (half == 2) {
        half = 1;
      } else {
        half = 2;
        year--;
      }
    }
    return periods;
  }
}
