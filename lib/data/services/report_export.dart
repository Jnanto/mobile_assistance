import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/schedule_format.dart';
import '../models/attendance_record.dart';
import '../models/course.dart';
import 'attendance_stats.dart';

/// Letra de cada estado para tablas compactas.
String statusLetter(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => 'P',
  AttendanceStatus.late => 'T',
  AttendanceStatus.absent => 'A',
  AttendanceStatus.justified => 'J',
  AttendanceStatus.review => 'R',
};

String statusLabel(AttendanceStatus status) => switch (status) {
  AttendanceStatus.present => 'Presente',
  AttendanceStatus.late => 'Tarde',
  AttendanceStatus.absent => 'Ausente',
  AttendanceStatus.justified => 'Justificado',
  AttendanceStatus.review => 'Por revisar',
};

String percent(double value) => '${(value * 100).round()} %';

/// Las fuentes estándar del PDF solo cubren Latin-1 (suficiente para el
/// español); otros caracteres se reemplazan para que no falle la generación.
String _safe(String text) =>
    String.fromCharCodes(text.runes.map((r) => r <= 0xFF ? r : 0x3F));

String _fileStamp(DateTime d) =>
    '${d.year}${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}';

String _slug(String text) => text
    .toLowerCase()
    .replaceAll(RegExp('[áà]'), 'a')
    .replaceAll(RegExp('[éè]'), 'e')
    .replaceAll(RegExp('[íì]'), 'i')
    .replaceAll(RegExp('[óò]'), 'o')
    .replaceAll(RegExp('[úùü]'), 'u')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp('[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

String courseReportFileName(Course course, DateTime now, String extension) =>
    'asistencia_${_slug(course.name)}_${_fileStamp(now)}.$extension';

pw.Widget _header(String title, List<String> lines) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(
      _safe(title),
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    pw.SizedBox(height: 4),
    for (final line in lines)
      pw.Text(_safe(line), style: const pw.TextStyle(fontSize: 10)),
    pw.SizedBox(height: 12),
  ],
);

pw.Widget _footer(pw.Context context, DateTime generatedAt) => pw.Row(
  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
  children: [
    pw.Text(
      _safe(
        'Generado por ${AppConfig.appName} el '
        '${ScheduleFormat.date(generatedAt)} a las '
        '${ScheduleFormat.clock(generatedAt)}',
      ),
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    ),
    pw.Text(
      'Página ${context.pageNumber} de ${context.pagesCount}',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
    ),
  ],
);

/// D6 · Reporte del curso en PDF.
Future<Uint8List> buildCourseReportPdf({
  required Course course,
  required CourseReport report,
  required DateTime generatedAt,
}) {
  final doc = pw.Document(title: 'Reporte de asistencia');
  final average = report.average;
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => _footer(context, generatedAt),
      build: (context) => [
        _header('Reporte de asistencia', [
          '${course.name} · ${course.group} · Periodo ${course.period}',
          'Docente: ${course.teacherName}',
          '${report.sessions.length} clases · ${report.students.length} '
              'estudiantes activos',
          'Promedio general: ${average == null ? 'sin datos' : percent(average)}'
              ' · Límite de inasistencia: '
              '${percent(AppConfig.maxAbsenceRate)}',
        ]),
        pw.TableHelper.fromTextArray(
          headers: [
            'Estudiante',
            'Código',
            'P',
            'T',
            'A',
            'J',
            'Asist.',
            'Faltas',
          ],
          data: [
            for (final row in report.students)
              [
                _safe(row.enrollment.name),
                row.enrollment.studentCode,
                row.stats.present + row.stats.review,
                row.stats.late,
                row.stats.absent,
                row.stats.justified,
                percent(row.stats.attendanceRate),
                percent(row.stats.absenceRate),
              ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
          cellAlignments: {for (var i = 2; i <= 7; i++) i: pw.Alignment.center},
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'P = presente (incluye "por revisar"), T = tarde, A = ausente, '
          'J = justificado. Las llegadas tarde y los justificados no cuentan '
          'como inasistencia.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        if (report.sessionRates.isNotEmpty) ...[
          pw.SizedBox(height: 16),
          pw.Text(
            'Asistencia por clase',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['Clase', 'Fecha', 'Esperados', 'Ausentes', 'Asistencia'],
            data: [
              for (final rate in report.sessionRates)
                [
                  '#${rate.session.number}',
                  _safe(ScheduleFormat.date(rate.session.startedAt)),
                  rate.expected,
                  rate.absent,
                  percent(rate.rate),
                ],
            ],
            headerStyle: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
            ),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// D6 · Reporte del curso en Excel: hoja "Resumen" y hoja "Detalle" con el
/// estado de cada estudiante en cada clase.
Uint8List buildCourseReportXlsx({
  required Course course,
  required CourseReport report,
}) {
  final excel = xls.Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet()!;
  excel.rename(defaultSheet, 'Resumen');
  final summary = excel['Resumen'];
  xls.TextCellValue t(String s) => xls.TextCellValue(s);

  summary.appendRow([t(course.name), t('${course.group} · ${course.period}')]);
  summary.appendRow([]);
  summary.appendRow([
    t('Estudiante'),
    t('Código'),
    t('Correo'),
    t('Clases'),
    t('Presente'),
    t('Tarde'),
    t('Ausente'),
    t('Justificado'),
    t('Por revisar'),
    t('% asistencia'),
    t('% inasistencia'),
    t('Nota'),
  ]);
  for (final row in report.students) {
    final s = row.stats;
    summary.appendRow([
      t(row.enrollment.name),
      t(row.enrollment.studentCode),
      t(row.enrollment.email),
      xls.IntCellValue(s.total),
      xls.IntCellValue(s.present),
      xls.IntCellValue(s.late),
      xls.IntCellValue(s.absent),
      xls.IntCellValue(s.justified),
      xls.IntCellValue(s.review),
      xls.DoubleCellValue((s.attendanceRate * 1000).round() / 10),
      xls.DoubleCellValue((s.absenceRate * 1000).round() / 10),
      if (row.enrollment.grade != null)
        xls.DoubleCellValue(row.enrollment.grade!)
      else
        null,
    ]);
  }

  final detail = excel['Detalle'];
  detail.appendRow([
    t('Estudiante'),
    t('Código'),
    for (final s in report.sessions)
      t('#${s.number} ${ScheduleFormat.shortDate(s.startedAt)}'),
  ]);
  for (final row in report.students) {
    final bySession = {
      for (final h in row.stats.history) h.session.id: h.status,
    };
    detail.appendRow([
      t(row.enrollment.name),
      t(row.enrollment.studentCode),
      for (final s in report.sessions)
        t(bySession[s.id] == null ? '-' : statusLetter(bySession[s.id]!)),
    ]);
  }
  detail.appendRow([]);
  detail.appendRow([
    t(
      'P = presente, T = tarde, A = ausente, J = justificado, '
      'R = por revisar, - = no inscrito aún',
    ),
  ]);
  return Uint8List.fromList(excel.encode()!);
}

/// E5 · Constancia de asistencia generada por SelvaCheck. No es un
/// certificado oficial de la universidad.
Future<Uint8List> buildAttendanceCertificatePdf({
  required String studentName,
  required String studentCode,
  required String email,
  required Course course,
  required StudentStats stats,
  required DateTime generatedAt,
}) {
  final doc = pw.Document(title: 'Constancia de asistencia');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(32),
      footer: (context) => _footer(context, generatedAt),
      build: (context) => [
        _header('Constancia de asistencia', [
          'Estudiante: $studentName · Código $studentCode',
          'Correo: $email',
          '${course.name} · ${course.group} · Periodo ${course.period}',
          'Docente: ${course.teacherName}',
        ]),
        pw.Text(
          _safe(
            'Clases registradas: ${stats.total} · Presente: ${stats.present} '
            '· Tarde: ${stats.late} · Ausente: ${stats.absent} · '
            'Justificado: ${stats.justified} · Por revisar: ${stats.review}',
          ),
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          _safe(
            'Asistencia: ${percent(stats.attendanceRate)} · Inasistencia: '
            '${percent(stats.absenceRate)} (límite '
            '${percent(AppConfig.maxAbsenceRate)})',
          ),
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headers: ['Clase', 'Fecha', 'Hora de registro', 'Estado'],
          data: [
            for (final h in stats.history)
              [
                '#${h.session.number}',
                _safe(ScheduleFormat.date(h.session.startedAt)),
                h.record?.markedAt == null
                    ? '-'
                    : _safe(ScheduleFormat.clock(h.record!.markedAt!)),
                statusLabel(h.status),
              ],
          ],
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green50),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          _safe(
            'Este documento fue generado automáticamente por '
            '${AppConfig.appName} a partir de los registros de asistencia '
            'del curso. No es un certificado oficial de la Universidad de la '
            'Amazonia.',
          ),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ),
  );
  return doc.save();
}

/// Guarda un archivo temporal y abre el menú de compartir de Android.
/// Es abstracto para poder sustituirlo en pruebas.
abstract class FileSharer {
  Future<void> share(Uint8List bytes, String fileName, String mimeType);
}

class DeviceFileSharer implements FileSharer {
  @override
  Future<void> share(Uint8List bytes, String fileName, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
  }
}

const pdfMime = 'application/pdf';
const xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
