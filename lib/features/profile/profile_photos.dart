import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repositories/photo_repository.dart';

/// Toma o elige una foto ya reducida (lado máximo [maxSide] px, JPEG).
abstract class PhotoPicker {
  Future<Uint8List?> pick({required bool fromCamera});
}

class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const maxSide = 384.0;

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    // image_picker pide el permiso de cámara si hace falta.
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: maxSide,
      maxHeight: maxSide,
      imageQuality: 75,
      preferredCameraDevice: CameraDevice.front,
    );
    return file?.readAsBytes();
  }
}

/// Fotos de perfil ya descargadas, por correo. Cada foto se pide una sola vez
/// (y Firestore la guarda además en el teléfono). Si no hay foto o no se
/// tiene permiso para verla, se queda en `null` y se muestran las iniciales.
class PhotoCache extends ChangeNotifier {
  PhotoCache(this._repo);

  final PhotoRepository _repo;
  final Map<String, Uint8List?> _photos = {};
  final Set<String> _loading = {};
  bool _disposed = false;

  /// La foto de [email], si ya se descargó; si no, empieza a pedirla.
  Uint8List? photoOf(String email) {
    final key = email.trim().toLowerCase();
    if (key.isEmpty) return null;
    if (!_photos.containsKey(key) && _loading.add(key)) _load(key);
    return _photos[key];
  }

  Future<void> _load(String key) async {
    Uint8List? photo;
    try {
      photo = await _repo.get(key);
    } catch (_) {
      // Sin permiso (p. ej., un estudiante viendo la de otro) o sin red.
    }
    _loading.remove(key);
    _photos[key] = photo;
    _notify();
  }

  Future<void> save(String email, Uint8List bytes) async {
    await _repo.save(email, bytes);
    _photos[email.toLowerCase()] = bytes;
    _notify();
  }

  Future<void> remove(String email) async {
    await _repo.delete(email);
    _photos[email.toLowerCase()] = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
