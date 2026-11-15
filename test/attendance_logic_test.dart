import 'dart:math';

import 'package:asis_selva_check/core/utils/attendance_checks.dart';
import 'package:asis_selva_check/data/models/attendance_record.dart';
import 'package:asis_selva_check/data/models/class_session.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

ClassSession _session({DateTime? start, String status = 'abierta'}) =>
    ClassSession.fromMap('s1', {
      'cursoId': 'c1',
      'docenteId': 'p1',
      'numero': 3,
      'inicio': Timestamp.fromDate(start ?? DateTime(2026, 11, 2, 14)),
      'ventanaPresenteMin': 10,
      'ventanaTardeMin': 5,
      'estado': status,
      'ubicacion': {'lat': 1.6145, 'lng': -75.6062, 'precision': 8},
      'radioMetros': 40,
      'wifi': ['AA:BB:CC:DD:EE:01'],
    });

AttendanceRecord _record({
  required DateTime at,
  String review = 'no_requerida',
  bool gpsOk = true,
  bool wifiOk = true,
  double? distance,
}) => AttendanceRecord.fromMap({
  'sesionId': 's1',
  'cursoId': 'c1',
  'email': 'laura@udla.edu.co',
  'nombre': 'Laura Méndez',
  'codigo': '20231145028',
  'marcadoEn': Timestamp.fromDate(at),
  'gpsOk': gpsOk,
  'wifiOk': wifiOk,
  'distanciaM': distance,
  'revision': review,
});

void main() {
  group('QrPayload', () {
    test('codifica y decodifica', () {
      final payload = const QrPayload('abc123', 'TOKEN').encode();
      expect(payload, 'SC1|abc123|TOKEN');
      final parsed = QrPayload.parse(payload)!;
      expect(parsed.sessionId, 'abc123');
      expect(parsed.token, 'TOKEN');
    });

    test('rechaza códigos ajenos', () {
      expect(QrPayload.parse(null), isNull);
      expect(QrPayload.parse('https://example.com'), isNull);
      expect(QrPayload.parse('SC1|abc'), isNull);
      expect(QrPayload.parse('XX1|abc|tok'), isNull);
      expect(QrPayload.parse('SC1||tok'), isNull);
    });

    test('genera tokens de 20 caracteres distintos', () {
      final a = QrPayload.newToken(Random(1));
      final b = QrPayload.newToken(Random(2));
      expect(a.length, 20);
      expect(a, isNot(b));
      expect(RegExp(r'^[A-Za-z0-9]+$').hasMatch(a), isTrue);
    });
  });

  group('GPS', () {
    test('un grado de latitud son ~111 km', () {
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 50));
    });

    test('dentro del radio', () {
      final check = evaluateGps(
        classLat: 1.6145,
        classLng: -75.6062,
        radiusMeters: 40,
        lat: 1.61460,
        lng: -75.6062,
        accuracy: 8,
        isMocked: false,
      );
      expect(check.ok, isTrue);
      expect(check.distance, closeTo(11, 1));
    });

    test('la imprecisión amplía el radio hasta 30 m como máximo', () {
      // ~89 m del aula.
      GpsCheck at(double accuracy) => evaluateGps(
        classLat: 1.6145,
        classLng: -75.6062,
        radiusMeters: 60,
        lat: 1.6153,
        lng: -75.6062,
        accuracy: accuracy,
        isMocked: false,
      );
      expect(at(10).ok, isFalse);
      expect(at(30).ok, isTrue);
      expect(at(500).ok, isTrue);
      final far = evaluateGps(
        classLat: 1.6145,
        classLng: -75.6062,
        radiusMeters: 40,
        lat: 1.6153,
        lng: -75.6062,
        accuracy: 500,
        isMocked: false,
      );
      expect(far.ok, isFalse);
      expect(far.issue, GpsIssue.outOfRange);
    });

    test('una ubicación simulada nunca pasa', () {
      final check = evaluateGps(
        classLat: 1.6145,
        classLng: -75.6062,
        radiusMeters: 40,
        lat: 1.6145,
        lng: -75.6062,
        accuracy: 5,
        isMocked: true,
      );
      expect(check.ok, isFalse);
      expect(check.issue, GpsIssue.mocked);
    });
  });

  group('WiFi', () {
    test('normaliza BSSID y descarta los inválidos', () {
      expect(normalizeBssid(' AA:BB:CC:DD:EE:01 '), 'aa:bb:cc:dd:ee:01');
      expect(normalizeBssid('02:00:00:00:00:00'), isNull);
      expect(normalizeBssid('<unknown ssid>'), isNull);
      expect(normalizeBssid(null), isNull);
    });

    test('pasa si el router está en la lista del docente', () {
      final classBssids = ['AA:BB:CC:DD:EE:01', 'aa:bb:cc:dd:ee:02'];
      expect(
        evaluateWifi(
          classBssids: classBssids,
          studentBssid: 'aa:bb:cc:dd:ee:01',
        ).ok,
        isTrue,
      );
      final other = evaluateWifi(
        classBssids: classBssids,
        studentBssid: 'aa:bb:cc:dd:ee:99',
      );
      expect(other.ok, isFalse);
      expect(other.issue, WifiIssue.notInClassroom);
      final none = evaluateWifi(classBssids: classBssids, studentBssid: null);
      expect(none.issue, WifiIssue.notConnected);
    });
  });

  group('Estados de asistencia', () {
    final session = _session();
    final start = DateTime(2026, 11, 2, 14);

    test('ventanas de la clase', () {
      expect(session.presentDeadline, DateTime(2026, 11, 2, 14, 10));
      expect(session.closesAt, DateTime(2026, 11, 2, 14, 15));
      expect(session.isAcceptingAt(DateTime(2026, 11, 2, 14, 14)), isTrue);
      expect(session.isAcceptingAt(DateTime(2026, 11, 2, 14, 16)), isFalse);
      expect(_session(status: 'cerrada').isAcceptingAt(start), isFalse);
      expect(session.wifiRequired, isTrue);
    });

    test('presente, tarde, por revisar y rechazado', () {
      expect(
        _record(at: start.add(const Duration(minutes: 9))).statusFor(session),
        AttendanceStatus.present,
      );
      expect(
        _record(at: start.add(const Duration(minutes: 12))).statusFor(session),
        AttendanceStatus.late,
      );
      final pending = _record(
        at: start.add(const Duration(minutes: 2)),
        review: 'pendiente',
        gpsOk: false,
        distance: 85,
      );
      expect(pending.statusFor(session), AttendanceStatus.review);
      expect(pending.timingStatus(session), AttendanceStatus.present);
      expect(pending.reviewReasons, ['Fuera del perímetro (85 m)']);
      expect(
        _record(at: start, review: 'aprobada').statusFor(session),
        AttendanceStatus.present,
      );
      expect(
        _record(at: start, review: 'rechazada').statusFor(session),
        AttendanceStatus.absent,
      );
    });
  });
}
