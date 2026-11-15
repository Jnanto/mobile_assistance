import 'dart:typed_data';

/// El archivo no es un libro de Excel 97-2003 legible.
class XlsFormatException implements Exception {
  const XlsFormatException(this.message);

  final String message;

  @override
  String toString() => 'XlsFormatException: $message';
}

/// Lector mínimo de libros de Excel 97-2003 (`.xls`, formato BIFF8), el que
/// descargan los docentes desde la plataforma de la universidad.
///
/// Solo extrae los valores de la primera hoja de cálculo: textos, números
/// y resultados de fórmulas. No lee formatos, fechas como fecha ni libros
/// protegidos con contraseña.
abstract final class XlsReader {
  /// Firma de un documento compuesto OLE2 (contenedor de los `.xls`).
  static const _signature = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

  static bool isXls(Uint8List bytes) {
    if (bytes.length < _signature.length) return false;
    for (var i = 0; i < _signature.length; i++) {
      if (bytes[i] != _signature[i]) return false;
    }
    return true;
  }

  /// Filas de la primera hoja; las celdas vacías quedan en `null`.
  static List<List<Object?>> readFirstSheet(Uint8List bytes) {
    if (!isXls(bytes)) {
      throw const XlsFormatException('No es un archivo de Excel 97-2003.');
    }
    try {
      final workbook = _CompoundFile(bytes).stream(const ['Workbook', 'Book']);
      return _BiffReader(workbook).firstSheetRows();
    } on RangeError {
      throw const XlsFormatException('El archivo .xls está dañado.');
    }
  }
}

// --- Contenedor OLE2 (Compound File Binary) ---

class _CompoundFile {
  _CompoundFile(this._bytes) : _data = ByteData.sublistView(_bytes) {
    if (_bytes.length < 512) _fail();
    _sectorSize = 1 << _u16(0x1E);
    _miniSectorSize = 1 << _u16(0x20);
    _miniCutoff = _u32(0x38);
    if (_sectorSize < 128 || _sectorSize > 65536) _fail();
    _fat = _readFat();
  }

  static const _endOfChain = 0xFFFFFFFE;
  static const _free = 0xFFFFFFFF;

  final Uint8List _bytes;
  final ByteData _data;
  late final int _sectorSize;
  late final int _miniSectorSize;
  late final int _miniCutoff;
  late final List<int> _fat;

  int _u16(int offset) => _data.getUint16(offset, Endian.little);
  int _u32(int offset) => _data.getUint32(offset, Endian.little);

  Never _fail() =>
      throw const XlsFormatException('El archivo .xls está dañado.');

  int _sectorOffset(int sector) => 512 + sector * _sectorSize;

  List<int> _sectorInts(int sector) {
    final start = _sectorOffset(sector);
    if (start + _sectorSize > _bytes.length) _fail();
    return [
      for (var i = 0; i < _sectorSize; i += 4)
        _data.getUint32(start + i, Endian.little),
    ];
  }

  List<int> _readFat() {
    final fatSectors = <int>[];
    final count = _u32(0x2C);
    for (var i = 0; i < 109 && fatSectors.length < count; i++) {
      fatSectors.add(_u32(0x4C + i * 4));
    }
    var difat = _u32(0x44);
    var guard = 0;
    while (fatSectors.length < count && difat < _endOfChain) {
      if (++guard > 10000) _fail();
      final entries = _sectorInts(difat);
      for (var i = 0; i < entries.length - 1; i++) {
        if (fatSectors.length < count) fatSectors.add(entries[i]);
      }
      difat = entries.last;
    }
    return [for (final sector in fatSectors) ..._sectorInts(sector)];
  }

  List<int> _chain(int start, List<int> table) {
    final chain = <int>[];
    var sector = start;
    while (sector != _endOfChain && sector != _free) {
      if (sector >= table.length || chain.length > table.length) _fail();
      chain.add(sector);
      sector = table[sector];
    }
    return chain;
  }

  Uint8List _readChain(int start) {
    final builder = BytesBuilder(copy: false);
    for (final sector in _chain(start, _fat)) {
      final offset = _sectorOffset(sector);
      if (offset + _sectorSize > _bytes.length) _fail();
      builder.add(Uint8List.sublistView(_bytes, offset, offset + _sectorSize));
    }
    return builder.takeBytes();
  }

  /// Contenido del primer flujo cuyo nombre esté en [names].
  Uint8List stream(List<String> names) {
    final directory = _readChain(_u32(0x30));
    final dir = ByteData.sublistView(directory);
    _DirEntry? root;
    _DirEntry? found;
    for (var offset = 0; offset + 128 <= directory.length; offset += 128) {
      final nameLength = dir.getUint16(offset + 0x40, Endian.little);
      final type = directory[offset + 0x42];
      if (nameLength < 2 || nameLength > 64) continue;
      final units = [
        for (var i = 0; i < nameLength - 2; i += 2)
          dir.getUint16(offset + i, Endian.little),
      ];
      final entry = _DirEntry(
        name: String.fromCharCodes(units),
        type: type,
        start: dir.getUint32(offset + 0x74, Endian.little),
        size: dir.getUint32(offset + 0x78, Endian.little),
      );
      if (type == 5) root = entry;
      if (type == 2 && found == null && names.contains(entry.name)) {
        found = entry;
      }
    }
    if (found == null) {
      throw const XlsFormatException(
        'El archivo no contiene un libro de Excel.',
      );
    }

    final Uint8List content;
    if (found.size < _miniCutoff) {
      if (root == null) _fail();
      final miniStream = _readChain(root.start);
      final miniFat = _u32(0x3C) >= _endOfChain
          ? const <int>[]
          : _bytesToInts(_readChain(_u32(0x3C)));
      final builder = BytesBuilder(copy: false);
      for (final sector in _chain(found.start, miniFat)) {
        final offset = sector * _miniSectorSize;
        if (offset + _miniSectorSize > miniStream.length) _fail();
        builder.add(
          Uint8List.sublistView(miniStream, offset, offset + _miniSectorSize),
        );
      }
      content = builder.takeBytes();
    } else {
      content = _readChain(found.start);
    }
    if (content.length < found.size) _fail();
    return Uint8List.sublistView(content, 0, found.size);
  }

  static List<int> _bytesToInts(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return [
      for (var i = 0; i + 4 <= bytes.length; i += 4)
        data.getUint32(i, Endian.little),
    ];
  }
}

class _DirEntry {
  const _DirEntry({
    required this.name,
    required this.type,
    required this.start,
    required this.size,
  });

  final String name;
  final int type;
  final int start;
  final int size;
}

// --- Registros BIFF8 ---

class _Record {
  const _Record(this.type, this.data);

  final int type;
  final Uint8List data;
}

class _BiffReader {
  _BiffReader(this._stream) : _view = ByteData.sublistView(_stream);

  static const _bof = 0x0809;
  static const _eof = 0x000A;
  static const _filePass = 0x002F;
  static const _boundSheet = 0x0085;
  static const _sst = 0x00FC;
  static const _continue = 0x003C;
  static const _labelSst = 0x00FD;
  static const _label = 0x0204;
  static const _number = 0x0203;
  static const _rk = 0x027E;
  static const _mulRk = 0x00BD;
  static const _formula = 0x0006;
  static const _string = 0x0207;
  static const _boolErr = 0x0205;

  final Uint8List _stream;
  final ByteData _view;

  Never _fail([String message = 'El archivo .xls está dañado.']) =>
      throw XlsFormatException(message);

  /// Registros desde [offset] hasta el EOF de esa sección.
  List<_Record> _records(int offset) {
    final records = <_Record>[];
    var position = offset;
    while (position + 4 <= _stream.length) {
      final type = _view.getUint16(position, Endian.little);
      final length = _view.getUint16(position + 2, Endian.little);
      final start = position + 4;
      if (start + length > _stream.length) _fail();
      records.add(
        _Record(type, Uint8List.sublistView(_stream, start, start + length)),
      );
      position = start + length;
      if (type == _eof) break;
    }
    return records;
  }

  List<List<Object?>> firstSheetRows() {
    final globals = _records(0);
    if (globals.isEmpty || globals.first.type != _bof) {
      _fail('No es un archivo de Excel 97-2003.');
    }
    final version = ByteData.sublistView(globals.first.data)
        .getUint16(0, Endian.little);
    if (version != 0x0600) {
      _fail(
        'El archivo usa una versión de Excel anterior a 97. Ábrelo y '
        'guárdalo como .xlsx.',
      );
    }

    int? sheetOffset;
    var strings = const <String>[];
    for (var i = 0; i < globals.length; i++) {
      final record = globals[i];
      switch (record.type) {
        case _filePass:
          _fail('El archivo está protegido con contraseña.');
        case _boundSheet:
          // Tipo de hoja 0 = hoja de cálculo (no gráficos ni macros).
          if (sheetOffset == null &&
              record.data.length >= 6 &&
              record.data[5] == 0) {
            sheetOffset = ByteData.sublistView(record.data)
                .getUint32(0, Endian.little);
          }
        case _sst:
          final chunks = [record.data];
          while (i + 1 < globals.length && globals[i + 1].type == _continue) {
            chunks.add(globals[++i].data);
          }
          strings = _readSst(chunks);
      }
    }
    if (sheetOffset == null) _fail('El archivo no tiene hojas de cálculo.');

    final cells = <int, Map<int, Object?>>{};
    void put(int row, int col, Object? value) =>
        (cells[row] ??= {})[col] = value;

    final sheet = _records(sheetOffset);
    for (var i = 0; i < sheet.length; i++) {
      final record = sheet[i];
      final data = ByteData.sublistView(record.data);
      int u16(int offset) => data.getUint16(offset, Endian.little);
      switch (record.type) {
        case _labelSst:
          final index = data.getUint32(6, Endian.little);
          if (index < strings.length) put(u16(0), u16(2), strings[index]);
        case _label:
          put(u16(0), u16(2), _ChunkReader([record.data], 6).string(16));
        case _number:
          put(u16(0), u16(2), data.getFloat64(6, Endian.little));
        case _rk:
          put(u16(0), u16(2), _rkValue(data.getUint32(6, Endian.little)));
        case _mulRk:
          final row = u16(0);
          var col = u16(2);
          for (var at = 4; at + 6 <= record.data.length - 2; at += 6) {
            put(row, col++, _rkValue(data.getUint32(at + 2, Endian.little)));
          }
        case _formula:
          final row = u16(0);
          final col = u16(2);
          final isSpecial = u16(12) == 0xFFFF;
          if (!isSpecial) {
            put(row, col, data.getFloat64(6, Endian.little));
          } else if (record.data[6] == 0 &&
              i + 1 < sheet.length &&
              sheet[i + 1].type == _string) {
            put(row, col, _ChunkReader([sheet[++i].data], 0).string(16));
          }
        case _boolErr:
          if (record.data[7] == 0) put(u16(0), u16(2), record.data[6] != 0);
      }
    }

    if (cells.isEmpty) return const [];
    final lastRow = cells.keys.reduce((a, b) => a > b ? a : b);
    return [
      for (var row = 0; row <= lastRow; row++) _rowList(cells[row] ?? const {}),
    ];
  }

  static List<Object?> _rowList(Map<int, Object?> row) {
    if (row.isEmpty) return const [];
    final last = row.keys.reduce((a, b) => a > b ? a : b);
    return [for (var col = 0; col <= last; col++) row[col]];
  }

  /// Número comprimido "RK": entero de 30 bits o los 30 bits altos de un
  /// double, opcionalmente dividido entre 100.
  static num _rkValue(int rk) {
    num value;
    if (rk & 0x02 != 0) {
      value = (rk & 0xFFFFFFFF).toSigned(32) >> 2;
    } else {
      final bits = ByteData(8)
        ..setUint32(0, 0, Endian.little)
        ..setUint32(4, rk & 0xFFFFFFFC, Endian.little);
      value = bits.getFloat64(0, Endian.little);
    }
    if (rk & 0x01 != 0) value = value / 100;
    return value;
  }

  static List<String> _readSst(List<Uint8List> chunks) {
    final reader = _ChunkReader(chunks, 0);
    reader.u32(); // Total de apariciones.
    final unique = reader.u32();
    final strings = <String>[];
    for (var i = 0; i < unique && !reader.atEnd; i++) {
      strings.add(reader.string(16, splitAware: true));
    }
    return strings;
  }
}

/// Lee datos que pueden continuar en registros CONTINUE. Cuando los
/// caracteres de un texto se parten entre registros, el siguiente empieza
/// con un byte que indica si siguen comprimidos (1 byte) o en UTF-16.
class _ChunkReader {
  _ChunkReader(this._chunks, this._offset);

  final List<Uint8List> _chunks;
  var _index = 0;
  int _offset;

  bool get atEnd =>
      _index >= _chunks.length ||
      (_index == _chunks.length - 1 && _offset >= _chunks[_index].length);

  void _advanceIfNeeded() {
    while (_index < _chunks.length && _offset >= _chunks[_index].length) {
      _index++;
      _offset = 0;
    }
    if (_index >= _chunks.length) {
      throw const XlsFormatException('El archivo .xls está dañado.');
    }
  }

  int u8() {
    _advanceIfNeeded();
    return _chunks[_index][_offset++];
  }

  int u16() => u8() | (u8() << 8);

  int u32() => u16() | (u16() << 16);

  void skip(int count) {
    for (var i = 0; i < count; i++) {
      u8();
    }
  }

  /// Texto Unicode de BIFF8 con largo de [lengthBits] bits.
  String string(int lengthBits, {bool splitAware = false}) {
    final length = lengthBits == 16 ? u16() : u8();
    final flags = u8();
    var wide = flags & 0x01 != 0;
    final runs = flags & 0x08 != 0 ? u16() : 0;
    final extSize = flags & 0x04 != 0 ? u32() : 0;

    final units = <int>[];
    while (units.length < length) {
      if (splitAware &&
          _index < _chunks.length &&
          _offset >= _chunks[_index].length) {
        _index++;
        _offset = 0;
        wide = u8() & 0x01 != 0;
      }
      units.add(wide ? u16() : u8());
    }
    skip(runs * 4 + extSize);
    return String.fromCharCodes(units);
  }
}
