import 'dart:convert';

import 'package:asis_selva_check/core/theme/app_theme.dart';
import 'package:asis_selva_check/data/models/app_user.dart';
import 'package:asis_selva_check/data/repositories/attendance_repository.dart';
import 'package:asis_selva_check/data/repositories/course_repository.dart';
import 'package:asis_selva_check/data/repositories/photo_repository.dart';
import 'package:asis_selva_check/data/repositories/user_repository.dart';
import 'package:asis_selva_check/data/services/device_services.dart';
import 'package:asis_selva_check/data/services/profile_services.dart';
import 'package:asis_selva_check/data/services/report_export.dart';
import 'package:asis_selva_check/features/auth/providers/auth_provider.dart';
import 'package:asis_selva_check/features/auth/providers/session_controller.dart';
import 'package:asis_selva_check/features/profile/profile_controllers.dart';
import 'package:asis_selva_check/features/profile/profile_photos.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Sustituto de AuthProvider con un perfil fijo.
class FakeAuth extends ChangeNotifier implements AuthProvider {
  FakeAuth(this._profile, {this.binding = DeviceBinding.thisDevice});

  AppUser _profile;
  final DeviceBinding binding;
  String? passwordError;
  final List<(String, String)> passwordChanges = [];

  @override
  AppUser? get profile => _profile;

  @override
  AuthStatus get status => _profile.role == UserRole.teacher
      ? AuthStatus.teacher
      : AuthStatus.student;

  @override
  DeviceIdentity? get device =>
      const DeviceIdentity(id: testDeviceId, model: 'Teléfono de prueba');

  @override
  DeviceBinding get deviceBinding => binding;

  @override
  Future<String?> changePassword(String current, String next) async {
    passwordChanges.add((current, next));
    return passwordError;
  }

  @override
  Future<String?> setDefaultPresentMinutes(int minutes) async {
    _profile = AppUser(
      uid: _profile.uid,
      name: _profile.name,
      email: _profile.email,
      role: _profile.role,
      linked: true,
      defaultPresentMinutes: minutes,
    );
    notifyListeners();
    return null;
  }

  @override
  String? get email => _profile.email;

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const teacher = AppUser(
  uid: 'p1',
  name: 'Oscar Patiño',
  email: 'oscar@udla.edu.co',
  role: UserRole.teacher,
  linked: true,
);

const student = AppUser(
  uid: 's1',
  name: 'Laura Méndez',
  email: 'laura@udla.edu.co',
  role: UserRole.student,
  studentCode: '20231145028',
  linked: true,
);

Map<String, dynamic> courseData({
  String name = 'Lógica y Algoritmos II',
  String status = 'activo',
}) => {
  'nombre': name,
  'codigo': 'IS-301',
  'grupo': 'Grupo 1',
  'periodo': '2026-2',
  'docenteId': 'p1',
  'docenteNombre': 'Oscar Patiño',
  'dias': [1, 3],
  'horaInicio': 840,
  'horaFin': 960,
  'bloque': 'Bloque 7',
  'salon': 'Salón 7205',
  'radioMetros': 40,
  'color': 0,
  'estado': status,
};

Map<String, dynamic> enrollmentData(
  String courseId,
  String email,
  String name, {
  String status = 'activo',
}) => {
  'cursoId': courseId,
  'email': email,
  'nombre': name,
  'codigo': '20231145028',
  'estado': status,
};

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.doc('cursos/c1').set(courseData());
  await db
      .doc('cursos/c2')
      .set(courseData(name: 'Programación Móvil', status: 'borrador'));
  await db
      .doc('inscripciones/c1_laura@udla.edu.co')
      .set(enrollmentData('c1', 'laura@udla.edu.co', 'Laura Méndez'));
  await db
      .doc('inscripciones/c1_carlos@udla.edu.co')
      .set(enrollmentData('c1', 'carlos@udla.edu.co', 'Carlos Ruiz'));
  await db
      .doc('inscripciones/c2_laura@udla.edu.co')
      .set(enrollmentData('c2', 'laura@udla.edu.co', 'Laura Méndez'));
  return db;
}

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeFirebaseFirestore db,
  AppUser user = teacher,
  LocationService? location,
  WifiService? wifi,
  FileSharer? sharer,
  PhotoPicker? picker,
  FakeAuth? auth,
  PreferencesStore? prefs,
  ReminderService? reminders,
  BiometricService? biometric,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, state) => screen),
      GoRoute(
        path: '/docente/cursos/:id',
        builder: (context, state) =>
            Text('detalle ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/docente/cursos/:id/estudiantes/:email',
        builder: (context, state) =>
            Text('ficha ${state.pathParameters['email']}'),
      ),
      GoRoute(
        path: '/docente/clase/:id',
        builder: (context, state) =>
            Text('clase en vivo ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/estudiante/clase/:id/resultado',
        builder: (context, state) =>
            Text('resultado ${state.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<CourseRepository>.value(
          value: CourseRepository(firestore: db),
        ),
        Provider<AttendanceRepository>.value(
          value: AttendanceRepository(firestore: db),
        ),
        Provider<LocationService>.value(
          value: location ?? FakeLocationService(),
        ),
        Provider<WifiService>.value(value: wifi ?? FakeWifiService()),
        Provider<FileSharer>.value(value: sharer ?? FakeFileSharer()),
        Provider<PhotoPicker>.value(value: picker ?? FakePhotoPicker()),
        ChangeNotifierProvider<PhotoCache>(
          create: (_) => PhotoCache(PhotoRepository(firestore: db)),
        ),
        Provider<UserRepository>.value(value: UserRepository(firestore: db)),
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth ?? FakeAuth(user),
        ),
        ChangeNotifierProvider<SessionController>(
          create: (context) => SessionController(
            prefs ??= InMemoryPreferences(),
            context.read<AuthProvider>(),
          ),
        ),
        ChangeNotifierProvider<RemindersController>(
          create: (_) => RemindersController(
            prefs ??= InMemoryPreferences(),
            reminders ?? FakeReminderService(),
          ),
        ),
        ChangeNotifierProvider<AppLockController>(
          create: (_) => AppLockController(
            prefs ??= InMemoryPreferences(),
            biometric ?? FakeBiometricService(),
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await pumpFor(tester, const Duration(seconds: 1));
  }
}

/// Avanza el tiempo en pasos cortos (para pantallas con temporizadores, donde
/// pumpAndSettle no termina nunca).
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Ubicación fija; por defecto, en el aula de [classLat]/[classLng].
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.lat = classLat,
    this.lng = classLng,
    this.accuracy = 8,
    this.isMocked = false,
    this.error,
  });

  final double lat;
  final double lng;
  final double accuracy;
  final bool isMocked;
  final LocationProblem? error;

  @override
  Future<LocationReading> current() async {
    if (error != null) throw LocationException(error!);
    return LocationReading(
      latitude: lat,
      longitude: lng,
      accuracy: accuracy,
      isMocked: isMocked,
    );
  }

  @override
  Future<void> openSettingsFor(LocationProblem problem) async {}
}

class FakeWifiService implements WifiService {
  FakeWifiService({this.connected = classBssid, this.nearby = const []});

  final String? connected;
  final List<String> nearby;

  @override
  Future<String?> connectedBssid() async => connected;

  @override
  Future<List<String>> nearbyBssids() async => nearby;
}

const classLat = 1.6145;
const classLng = -75.6062;
const classBssid = 'aa:bb:cc:dd:ee:01';

/// Guarda lo que se "compartió" en lugar de abrir el menú de Android.
class FakeFileSharer implements FileSharer {
  final List<(String, String, int)> shared = [];

  @override
  Future<void> share(Uint8List bytes, String fileName, String mimeType) async {
    shared.add((fileName, mimeType, bytes.length));
  }
}

const testDeviceId = 'TELEFONO_DE_PRUEBA_0001';

class InMemoryPreferences implements PreferencesStore {
  final Map<String, Object> values = {};

  @override
  String? getString(String key) => values[key] as String?;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  bool getBool(String key, {bool fallback = false}) =>
      (values[key] as bool?) ?? fallback;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;
}

class FakeReminderService implements ReminderService {
  FakeReminderService({this.granted = true});

  final bool granted;
  List<WeeklyReminder> scheduled = [];
  int cancelCount = 0;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<void> schedule(List<WeeklyReminder> reminders) async =>
      scheduled = reminders;

  @override
  Future<void> cancelAll() async {
    scheduled = [];
    cancelCount++;
  }
}

class FakeBiometricService implements BiometricService {
  FakeBiometricService({this.available = true, this.succeeds = true});

  final bool available;
  bool succeeds;
  int prompts = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeeds;
  }
}

/// Selector de fotos falso: devuelve una imagen fija (o nada si se canceló).
class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker({this.photo});

  /// JPEG válido de 8×8 px.
  static final Uint8List tinyJpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAoHBwgHBgoICAgLCgoLDhgQDg0NDh0VFhEYIx8lJCIfIiEmKzcvJik0KSEiMEExNDk7Pj4+JS5ESUM8SDc9Pjv/2wBDAQoLCw4NDhwQEBw7KCIoOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozv/wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDiaKKKxPJP/9k=',
  );

  final Uint8List? photo;
  final List<bool> requests = [];

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    requests.add(fromCamera);
    return photo ?? tinyJpeg;
  }
}
