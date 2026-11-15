import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/pre_registration.dart';

/// Acceso a `usuarios` y `preregistros` en Firestore.
class UserRepository {
  UserRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('usuarios');

  CollectionReference<Map<String, dynamic>> get _preRegistrations =>
      _db.collection('preregistros');

  /// Emite el perfil del usuario, o `null` si no existe en el servidor.
  /// Se ignora el "no existe" que viene solo de la caché local.
  Stream<AppUser?> watchUser(String uid) => _users
      .doc(uid)
      .snapshots()
      .where((snap) => snap.exists || !snap.metadata.isFromCache)
      .map(
        (snap) => snap.exists ? AppUser.fromMap(snap.id, snap.data()!) : null,
      );

  Future<AppUser?> getUser(String uid) async {
    final snap = await _users.doc(uid).get();
    return snap.exists ? AppUser.fromMap(snap.id, snap.data()!) : null;
  }

  Future<void> createStudentProfile({
    required String uid,
    required String name,
    required String studentCode,
    required String email,
  }) => _users.doc(uid).set({
    'nombre': name,
    'codigo': studentCode,
    'email': email,
    'rol': UserRole.student.value,
    'vinculado': false,
    'creadoEn': FieldValue.serverTimestamp(),
  });

  Future<PreRegistration?> getPreRegistration(String email) async {
    final snap = await _preRegistrations.doc(email).get();
    return snap.exists ? PreRegistration.fromMap(snap.id, snap.data()!) : null;
  }

  /// Las reglas de Firestore solo lo permiten si existe un pre-registro con el
  /// mismo correo y código.
  Future<void> markLinked(String uid) => _users.doc(uid).update({
    'vinculado': true,
    'vinculadoEn': FieldValue.serverTimestamp(),
  });

  Future<void> deleteProfile(String uid) => _users.doc(uid).delete();

  /// Vincula la cuenta del estudiante a este teléfono (solo la primera vez;
  /// las reglas impiden cambiarlo).
  Future<void> bindDevice({
    required String uid,
    required String deviceId,
    required String model,
  }) => _users.doc(uid).update({
    'dispositivo': {
      'id': deviceId,
      'modelo': model,
      'vinculadoEn': FieldValue.serverTimestamp(),
    },
  });

  /// El docente desvincula el teléfono de un estudiante.
  Future<void> unbindDevice(String uid) =>
      _users.doc(uid).update({'dispositivo': FieldValue.delete()});

  /// Cuenta de un estudiante a partir de su correo (para el docente).
  Future<AppUser?> findByEmail(String email) async {
    final snap = await _users.where('email', isEqualTo: email).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.single;
    return AppUser.fromMap(doc.id, doc.data());
  }

  /// Datos personales y académicos que el usuario edita en su perfil. El
  /// correo y el código no se editan: identifican la cuenta.
  ///
  /// Con [renameInCourses] (docente que cambió su nombre), actualiza también
  /// `docenteNombre` en sus cursos en el mismo lote: o se guarda todo o nada.
  Future<void> updateProfile({
    required String uid,
    required String name,
    required String phone,
    String? program,
    String? department,
    bool renameInCourses = false,
  }) async {
    final batch = _db.batch();
    batch.update(_users.doc(uid), {
      'nombre': name,
      'telefono': phone,
      'programa': ?program,
      'dependencia': ?department,
    });
    if (renameInCourses) {
      final courses = await _db
          .collection('cursos')
          .where('docenteId', isEqualTo: uid)
          .get();
      for (final course in courses.docs) {
        batch.update(course.reference, {
          'docenteNombre': name,
          'actualizadoEn': FieldValue.serverTimestamp(),
        });
      }
    }
    await batch.commit();
  }

  Future<void> setDefaultPresentMinutes(String uid, int minutes) =>
      _users.doc(uid).update({'toleranciaPresenteMin': minutes});
}
