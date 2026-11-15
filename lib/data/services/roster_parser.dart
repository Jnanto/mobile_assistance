import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../../core/utils/validators.dart';
import '../models/roster_entry.dart';
import 'xls_reader.dart';

class RosterParseResult {
  const RosterParseResult(this.entries, this.errors);

  final List<RosterEntry> entries;
  final List<String> errors;
}

/// Lee una lista de estudiantes desde CSV, XLSX o XLS (Excel 97-2003, el
/// formato de las listas que descargan los docentes de la universidad).
///
/// Busca, entre las primeras filas, la que tenga los encabezados del correo,
/// el nombre y el código, en cualquier orden. Se aceptan tildes, mayúsculas y
/// variantes como "email", "MAIL_INST", "NOMBRECOMPLETO" o
/// "CODIGOESTUDIANTE". Las demás columnas se ignoran.
abstract final class RosterParser {
  static const _headerSearchRows = 10;

  static const formatHelp =
      'Puedes subir la lista tal como la descargas de la plataforma de la '
      'universidad (.xls). También se admiten archivos .xlsx o .csv con '
      'los encabezados correo, nombre y codigo, y una fila por estudiante. '
      'Las demás columnas se ignoran. Ejemplo:\n'
      'correo,nombre,codigo\n'
      'lmendez@udla.edu.co,Laura Sofía Méndez,20231145028';

  static RosterParseResult fromFile(String fileName, Uint8List bytes) {
    final lower = fileName.toLowerCase();
    final isExcel = lower.endsWith('.xls') || lower.endsWith('.xlsx');
    // Se decide por el contenido: hay .xls que en realidad son .xlsx.
    if (isExcel && XlsReader.isXls(bytes)) return fromXls(bytes);
    if (isExcel && _isZip(bytes)) return fromXlsx(bytes);
    if (lower.endsWith('.csv')) return fromCsv(_decodeText(bytes));
    if (isExcel) {
      return const RosterParseResult([], [
        'No se pudo leer el archivo de Excel. Ábrelo y guárdalo como .xlsx.',
      ]);
    }
    return const RosterParseResult([], [
      'Formato no soportado. Usa un archivo .xls, .xlsx o .csv.',
    ]);
  }

  static RosterParseResult fromXls(Uint8List bytes) {
    try {
      return fromRows(XlsReader.readFirstSheet(bytes));
    } on XlsFormatException catch (e) {
      return RosterParseResult([], [e.message]);
    }
  }

  static bool _isZip(Uint8List bytes) =>
      bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  static RosterParseResult fromCsv(String content) {
    final List<List<dynamic>> rows;
    try {
      rows = csv.decode(content);
    } catch (_) {
      return const RosterParseResult([], ['No se pudo leer el archivo CSV.']);
    }
    return fromRows(rows);
  }

  static RosterParseResult fromXlsx(Uint8List bytes) {
    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        return const RosterParseResult([], ['El archivo no tiene hojas.']);
      }
      final sheet = excel.tables.values.first;
      final rows = sheet.rows
          .map((row) => row.map((cell) => _cellText(cell?.value)).toList())
          .toList();
      return fromRows(rows);
    } catch (_) {
      return const RosterParseResult([], ['No se pudo leer el archivo XLSX.']);
    }
  }

  static RosterParseResult fromRows(List<List<Object?>> rows) {
    final dataRows = rows
        .map((row) => row.map(_text).toList())
        .where((row) => row.any((cell) => cell.isNotEmpty))
        .toList();
    if (dataRows.isEmpty) {
      return const RosterParseResult([], ['El archivo está vacío.']);
    }

    // Algunas descargas traen títulos antes de los encabezados.
    var headerRow = -1;
    var emailCol = -1, nameCol = -1, codeCol = -1;
    for (var r = 0; r < dataRows.length && r < _headerSearchRows; r++) {
      final header = dataRows[r].map(_normalizeHeader).toList();
      emailCol = header.indexWhere(
        (h) => h.contains('correo') || h.contains('mail'),
      );
      nameCol = header.indexWhere((h) => h.contains('nombre'));
      codeCol = header.indexWhere((h) => h.contains('codigo'));
      if (emailCol >= 0 && nameCol >= 0 && codeCol >= 0) {
        headerRow = r;
        break;
      }
    }
    if (headerRow < 0) {
      return const RosterParseResult([], [
        'Faltan encabezados. El archivo debe tener columnas de correo, '
            'nombre y codigo.',
      ]);
    }

    final entries = <RosterEntry>[];
    final errors = <String>[];
    final seen = <String>{};
    for (var i = headerRow + 1; i < dataRows.length; i++) {
      final row = dataRows[i];
      final rowNumber = i + 1;
      String cell(int col) => col < row.length ? row[col] : '';

      final email = Validators.normalizeEmail(cell(emailCol));
      final name = cell(nameCol).replaceAll(RegExp(r'\s+'), ' ');
      final code = cell(codeCol);
      final problem =
          Validators.institutionalEmail(email) ??
          Validators.fullName(name) ??
          Validators.studentCode(code);
      if (problem != null) {
        errors.add('Fila $rowNumber: $problem');
        continue;
      }
      if (!seen.add(email)) {
        errors.add('Fila $rowNumber: el correo $email está repetido.');
        continue;
      }
      entries.add(RosterEntry(email: email, name: name, studentCode: code));
    }
    return RosterParseResult(entries, errors);
  }

  /// Texto de una celda: los números enteros pierden el ".0".
  static String _text(Object? value) {
    if (value == null) return '';
    if (value is double && value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString().trim();
  }

  static Object? _cellText(CellValue? value) => switch (value) {
    null => null,
    IntCellValue(:final value) => value,
    DoubleCellValue(:final value) => value,
    _ => value.toString(),
  };

  static String _normalizeHeader(String header) {
    const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u'};
    var text = header.toLowerCase().trim();
    accents.forEach((from, to) => text = text.replaceAll(from, to));
    return text;
  }

  /// Excel en Windows suele guardar CSV en Latin-1; se intenta UTF-8 primero.
  static String _decodeText(Uint8List bytes) {
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return text.startsWith('﻿') ? text.substring(1) : text;
  }
}
