import 'dart:io';
import 'dart:typed_data';

import 'package:asis_selva_check/core/utils/schedule_format.dart';
import 'package:asis_selva_check/data/models/course.dart';
import 'package:asis_selva_check/data/models/enrollment.dart';
import 'package:asis_selva_check/data/services/roster_parser.dart';
import 'package:asis_selva_check/data/services/xls_reader.dart';
import 'package:flutter_test/flutter_test.dart';

Course _course({
  List<int> days = const [1, 3],
  int start = 840,
  int end = 960,
}) => Course.fromMap('c1', {
  'nombre': 'Lógica y Algoritmos II',
  'codigo': 'IS-301',
  'grupo': 'Grupo 1',
  'periodo': '2026-2',
  'docenteId': 'p1',
  'docenteNombre': 'Oscar Patiño',
  'dias': days,
  'horaInicio': start,
  'horaFin': end,
  'bloque': 'Bloque 7',
  'salon': 'Salón 7205',
  'radioMetros': 40,
  'color': 2,
  'estado': 'activo',
});

void main() {
  group('ScheduleFormat', () {
    test('días', () {
      expect(ScheduleFormat.days([3, 1]), 'Lun y Mié');
      expect(ScheduleFormat.days([1, 3, 5]), 'Lun, Mié y Vie');
      expect(ScheduleFormat.days([5]), 'Vie');
      expect(ScheduleFormat.days([]), 'Sin días');
    });

    test('horas', () {
      expect(ScheduleFormat.time(840), '2:00 p. m.');
      expect(ScheduleFormat.time(0), '12:00 a. m.');
      expect(ScheduleFormat.time(12 * 60 + 5), '12:05 p. m.');
      expect(ScheduleFormat.timeRange(840, 960), '2:00–4:00 p. m.');
      expect(ScheduleFormat.timeRange(600, 780), '10:00 a. m. – 1:00 p. m.');
    });

    test('periodos recientes', () {
      expect(ScheduleFormat.recentPeriods(DateTime(2026, 11, 1)), [
        '2026-2',
        '2026-1',
        '2025-2',
      ]);
      expect(ScheduleFormat.recentPeriods(DateTime(2026, 3, 1)), [
        '2026-1',
        '2025-2',
        '2025-1',
      ]);
    });
  });

  group('Course', () {
    test('un curso antiguo (horario único) se lee como encuentros', () {
      final course = _course();
      expect(course.meetings, hasLength(2));
      expect(course.meetings.map((m) => m.day), [1, 3]);
      expect(course.meetings.first.room, 'Salón 7205');
      final map = course.toMap();
      expect(map.containsKey('dias'), isFalse);
      expect(map['encuentros'], [
        {
          'dia': 1,
          'inicio': 840,
          'fin': 960,
          'bloque': 'Bloque 7',
          'salon': 'Salón 7205',
        },
        {
          'dia': 3,
          'inicio': 840,
          'fin': 960,
          'bloque': 'Bloque 7',
          'salon': 'Salón 7205',
        },
      ]);
      expect(Course.fromMap('c1', map).scheduleLabel, course.scheduleLabel);
      expect(course.scheduleLabel, 'Lun 2:00–4:00 p. m. · Mié 2:00–4:00 p. m.');
      expect(course.locationLabel, 'Bloque 7 · Salón 7205');
      expect(course.initials, 'LA');
    });

    test('encuentros con horario y salón propios', () {
      final course = Course.fromMap('c1', {
        'nombre': 'Programación Móvil',
        'encuentros': [
          {'dia': 5, 'inicio': 480, 'fin': 600, 'salon': 'Lab 4'},
          {
            'dia': 1,
            'inicio': 840,
            'fin': 960,
            'bloque': 'Bloque 7',
            'salon': 'Salón 7205',
          },
        ],
      });
      // Se ordenan por día.
      expect(course.meetings.first.day, 1);
      expect(
        course.scheduleLabel,
        'Lun 2:00–4:00 p. m. · Vie 8:00–10:00 a. m.',
      );
      expect(course.locationLabel, 'Bloque 7 · Salón 7205 / Lab 4');
      final friday = DateTime(2026, 11, 6, 9);
      expect(course.isOngoing(friday), isTrue);
      expect(course.meetingFor(friday)!.room, 'Lab 4');
      expect(
        course.currentOrNextToday(DateTime(2026, 11, 2, 13))!.room,
        'Salón 7205',
      );
      // Martes sin clase: se usa el primero.
      expect(course.meetingFor(DateTime(2026, 11, 3, 9))!.day, 1);
    });

    test('valida de 1 a 2 encuentros sin cruces', () {
      const a = CourseMeeting(
        day: 1,
        startMinutes: 840,
        endMinutes: 960,
        room: '7205',
      );
      expect(validateMeetings([a]), isNull);
      expect(validateMeetings([]), isNotNull);
      expect(
        validateMeetings([a, a.copyWith(day: 3), a.copyWith(day: 5)]),
        contains('Máximo 2'),
      );
      expect(
        validateMeetings([a, a.copyWith(startMinutes: 900, endMinutes: 1000)]),
        contains('se cruzan'),
      );
      expect(
        validateMeetings([a, a.copyWith(startMinutes: 960, endMinutes: 1080)]),
        isNull,
      );
      expect(validateMeetings([a.copyWith(endMinutes: 800)]), isNotNull);
      expect(validateMeetings([a.copyWith(room: ' ')]), contains('salón'));
    });

    test('clase en curso o más tarde hoy', () {
      final course = _course();
      final monday = DateTime(2026, 11, 2); // lunes
      expect(course.hasClassOn(monday), isTrue);
      expect(
        course.isLaterToday(monday.add(const Duration(hours: 13))),
        isTrue,
      );
      expect(course.isOngoing(monday.add(const Duration(hours: 15))), isTrue);
      expect(course.isOngoing(monday.add(const Duration(hours: 16))), isFalse);
      expect(course.hasClassOn(DateTime(2026, 11, 3)), isFalse); // martes
    });

    test('estado desconocido se trata como borrador', () {
      expect(CourseStatus.fromValue('raro'), CourseStatus.draft);
    });
  });

  test('Enrollment.docId', () {
    expect(Enrollment.docId('abc', 'x@udla.edu.co'), 'abc_x@udla.edu.co');
  });

  group('RosterParser', () {
    test('lee CSV con coma y encabezados en otro orden', () {
      final result = RosterParser.fromCsv(
        'Nombre,Código,Correo\n'
        'Laura Méndez,20231145028,LMendez@udla.edu.co\n'
        'Carlos Ruiz,202010089,cruiz@udla.edu.co\n',
      );
      expect(result.errors, isEmpty);
      expect(result.entries.length, 2);
      expect(result.entries.first.email, 'lmendez@udla.edu.co');
      expect(result.entries.first.studentCode, '20231145028');
    });

    test('lee CSV con punto y coma (Excel en español)', () {
      final result = RosterParser.fromCsv(
        'correo;nombre;codigo\r\nlmendez@udla.edu.co;Laura Méndez;20231145028\r\n',
      );
      expect(result.errors, isEmpty);
      expect(result.entries.single.name, 'Laura Méndez');
    });

    test('reporta filas inválidas y repetidas', () {
      final result = RosterParser.fromRows([
        ['correo', 'nombre', 'codigo'],
        ['a@udla.edu.co', 'Ana Pérez', '123456'],
        ['a@udla.edu.co', 'Ana Pérez', '123456'],
        ['b@gmail.com', 'Beto Gómez', '123456'],
        ['c@udla.edu.co', 'Carla', '123456'],
        ['d@udla.edu.co', 'Dora Ruiz', '12AB'],
        ['', '', ''],
      ]);
      expect(result.entries.length, 1);
      expect(result.errors.length, 4);
      expect(result.errors.first, startsWith('Fila 3'));
    });

    test('convierte códigos numéricos de Excel sin ".0"', () {
      final result = RosterParser.fromRows([
        ['correo', 'nombre', 'codigo'],
        ['a@udla.edu.co', 'Ana Pérez', 20231145028.0],
      ]);
      expect(result.entries.single.studentCode, '20231145028');
    });

    test('exige los encabezados', () {
      final result = RosterParser.fromRows([
        ['email', 'nombre'],
        ['a@udla.edu.co', 'Ana Pérez'],
      ]);
      expect(result.entries, isEmpty);
      expect(result.errors.single, contains('encabezados'));
    });

    test('rechaza extensiones no soportadas', () {
      final result = RosterParser.fromFile('lista.pdf', Uint8List(0));
      expect(result.errors.single, contains('Formato no soportado'));
    });

    test('reconoce los encabezados de la lista de la universidad', () {
      final result = RosterParser.fromRows([
        ['PROGRAMA', 'CODIGOESTUDIANTE', 'MAIL_INST', 'DOCUMENTO'],
        ['INGENIERIA DE SISTEMAS', 4245172970.0, 'A@udla.edu.co ', 1.0],
      ]);
      expect(
        result.errors,
        contains(contains('nombre')),
        reason: 'sin columna de nombre',
      );
      final withName = RosterParser.fromRows([
        ['CODIGOESTUDIANTE', 'MAIL_INST', 'NOMBRECOMPLETO'],
        [4245172970.0, 'A@udla.edu.co ', 'Alvarez  Rojas Laura'],
      ]);
      expect(withName.errors, isEmpty);
      final entry = withName.entries.single;
      expect(entry.studentCode, '4245172970');
      expect(entry.email, 'a@udla.edu.co');
      expect(entry.name, 'Alvarez Rojas Laura');
    });

    test('busca los encabezados después de filas de título', () {
      final result = RosterParser.fromRows([
        ['Lista de estudiantes'],
        ['Periodo 2026-2', null, 'Grupo 1'],
        [],
        ['nombre', 'correo', 'codigo'],
        ['Ana Pérez', 'ana@udla.edu.co', '20231145'],
      ]);
      expect(result.errors, isEmpty);
      expect(result.entries.single.name, 'Ana Pérez');
    });

    group('archivo .xls de la universidad', () {
      // Mismo formato que la descarga real (Excel 97-2003, encabezados
      // PROGRAMA, CODIGOESTUDIANTE, MAIL_INST, NOMBRECOMPLETO...), con
      // datos ficticios y 300 filas para que los textos compartidos
      // continúen en varios registros.
      final bytes = File('test/fixtures/lista_universidad.xls')
          .readAsBytesSync();

      test('lee todas las filas y columnas de la primera hoja', () {
        final rows = XlsReader.readFirstSheet(bytes);
        expect(rows, hasLength(301));
        expect(rows.first, [
          'PROGRAMA',
          'CODIGOESTUDIANTE',
          'FECHAMATRICULA',
          'MAIL_INST',
          'DOCUMENTO',
          'NOMBRECOMPLETO',
          'PENG_IDENTITARIO',
          'TELEFONO',
          'EPS',
        ]);
        expect(rows[1][0], 'INGENIERIA DE SISTEMAS');
        expect(rows[1][6], isNull);
        expect(rows[8][7], 3000000008);
      });

      test('importa los estudiantes sin errores', () {
        final result = RosterParser.fromFile('Lista_Movil.xls', bytes);
        expect(result.errors, isEmpty);
        expect(result.entries, hasLength(300));

        final first = result.entries.first;
        expect(first.studentCode, '20230001');
        expect(first.email, 'estudiante.prueba001@udla.edu.co');
        expect(
          first.name,
          'Apellidoprueba001 Segundoapellido Nombreuno Nombredos',
        );
        expect(result.entries[7].studentCode, '4000000008');
        expect(result.entries[6].name, 'Đorđe Muñoz Peña');
        for (var i = 0; i < 300; i++) {
          final n = (i + 1).toString().padLeft(3, '0');
          expect(result.entries[i].email, 'estudiante.prueba$n@udla.edu.co');
          if (i != 6) {
            expect(
              result.entries[i].name,
              'Apellidoprueba$n Segundoapellido Nombreuno Nombredos',
            );
          }
        }
      });

      test('un .xls dañado da un mensaje claro', () {
        final broken = Uint8List.fromList([...bytes.take(600)]);
        final result = RosterParser.fromFile('lista.xls', broken);
        expect(result.entries, isEmpty);
        expect(result.errors.single, contains('dañado'));
      });

      test('un .xls que no es Excel se rechaza', () {
        final result = RosterParser.fromFile(
          'lista.xls',
          Uint8List.fromList('<html><table>'.codeUnits),
        );
        expect(result.errors.single, contains('No se pudo leer'));
      });
    });
  });
}
