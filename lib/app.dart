import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/attendance_repository.dart';
import 'data/repositories/course_repository.dart';
import 'data/repositories/photo_repository.dart';
import 'data/repositories/user_repository.dart';
import 'data/services/auth_service.dart';
import 'data/services/device_services.dart';
import 'data/services/profile_services.dart';
import 'data/services/report_export.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/auth/providers/session_controller.dart';
import 'features/profile/app_lock_gate.dart';
import 'features/profile/profile_controllers.dart';
import 'features/profile/profile_photos.dart';

class SelvaCheckApp extends StatelessWidget {
  const SelvaCheckApp({super.key, required this.prefs});

  final PreferencesStore prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthService>(create: (_) => AuthService()),
        Provider<UserRepository>(create: (_) => UserRepository()),
        Provider<CourseRepository>(create: (_) => CourseRepository()),
        Provider<AttendanceRepository>(create: (_) => AttendanceRepository()),
        Provider<LocationService>(create: (_) => DeviceLocationService()),
        Provider<WifiService>(create: (_) => DeviceWifiService()),
        Provider<FileSharer>(create: (_) => DeviceFileSharer()),
        Provider<PhotoRepository>(create: (_) => PhotoRepository()),
        Provider<PhotoPicker>(create: (_) => DevicePhotoPicker()),
        ChangeNotifierProvider<PhotoCache>(
          create: (context) => PhotoCache(context.read<PhotoRepository>()),
        ),
        Provider<PreferencesStore>.value(value: prefs),
        Provider<DeviceIdentityService>(
          create: (_) => DeviceIdentityServiceImpl(prefs),
        ),
        Provider<ReminderService>(create: (_) => LocalReminderService()),
        Provider<BiometricService>(create: (_) => LocalBiometricService()),
        ChangeNotifierProvider<AuthProvider>(
          create: (context) => AuthProvider(
            context.read<AuthService>(),
            context.read<UserRepository>(),
            context.read<DeviceIdentityService>(),
          )..start(),
        ),
        ChangeNotifierProvider<SessionController>(
          create: (context) =>
              SessionController(prefs, context.read<AuthProvider>()),
        ),
        ChangeNotifierProvider<RemindersController>(
          create: (context) =>
              RemindersController(prefs, context.read<ReminderService>()),
        ),
        ChangeNotifierProvider<AppLockController>(
          create: (context) =>
              AppLockController(prefs, context.read<BiometricService>()),
        ),
      ],
      child: const _RouterApp(),
    );
  }
}

class _RouterApp extends StatefulWidget {
  const _RouterApp();

  @override
  State<_RouterApp> createState() => _RouterAppState();
}

class _RouterAppState extends State<_RouterApp> {
  late final GoRouter _router = createRouter(context.read<AuthProvider>());

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: (context, child) => SessionActivityDetector(
        session: context.read<SessionController>(),
        child: AppLockGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Se muestra si Firebase no está configurado (falta `flutterfire configure`).
class FirebaseSetupErrorApp extends StatelessWidget {
  const FirebaseSetupErrorApp({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Firebase no está configurado',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ejecuta "flutterfire configure" en la raíz del proyecto '
                  'para generar lib/firebase_options.dart y vuelve a '
                  'compilar.',
                ),
                const SizedBox(height: 12),
                Text('$error', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
