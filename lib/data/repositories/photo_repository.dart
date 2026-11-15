import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Fotos de perfil en `fotos/{correo}`: JPEG reducido guardado como texto
/// base64 (Firebase Storage exige el plan Blaze).
class PhotoRepository {
  PhotoRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Tamaño máximo de la imagen (las reglas admiten 150 000 caracteres en
  /// base64, que equivalen a unos 112 KB).
  static const maxBytes = 110 * 1024;

  DocumentReference<Map<String, dynamic>> _doc(String email) =>
      _db.collection('fotos').doc(email.toLowerCase());

  Future<Uint8List?> get(String email) async {
    final snap = await _doc(email).get();
    final data = snap.data()?['imagen'];
    if (data is! String || data.isEmpty) return null;
    return base64Decode(data);
  }

  Future<void> save(String email, Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw ArgumentError('La foto supera ${maxBytes ~/ 1024} KB.');
    }
    return _doc(email).set({
      'imagen': base64Encode(bytes),
      'actualizadoEn': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String email) => _doc(email).delete();
}
