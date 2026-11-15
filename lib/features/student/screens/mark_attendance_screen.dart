import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/attendance_checks.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_session.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/device_services.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../auth/providers/auth_provider.dart';
import 'qr_scanner_screen.dart';

/// Abre el escáner y devuelve el texto leído. Se puede reemplazar en pruebas.
typedef QrScanLauncher = Future<String?> Function(BuildContext context);

Future<String?> defaultQrScan(BuildContext context) => Navigator.of(context)
    .push<String>(MaterialPageRoute(builder: (_) => const QrScannerScreen()));

/// E2 · Marcar presente: GPS, WiFi y, al final, escanear el QR.
class MarkAttendanceScreen extends StatefulWidget {
  const MarkAttendanceScreen({
    super.key,
    required this.sessionId,
    this.scan = defaultQrScan,
  });

  final String sessionId;
  final QrScanLauncher scan;

  @override
  State<MarkAttendanceScreen> createState() => _MarkAttendanceScreenState();
}

class _MarkAttendanceScreenState extends State<MarkAttendanceScreen> {
  StreamSubscription<ClassSession?>? _sessionSub;
  ClassSession? _session;
  Stream<AttendanceRecord?>? _myRecord;
  bool _loaded = false;
  Timer? _ticker;

  bool _checkingGps = false;
  GpsCheck? _gps;
  LocationException? _gpsError;

  bool _checkingWifi = false;
  WifiCheck? _wifi;

  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sessionSub = context
        .read<AttendanceRepository>()
        .watchSession(widget.sessionId)
        .listen(_onSession, onError: (Object _) => _onSession(null));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _onSession(ClassSession? session) {
    final first = !_loaded;
    setState(() {
      _session = session;
      _loaded = true;
    });
    if (first && session != null) {
      _myRecord = context.read<AttendanceRepository>().watchMyRecord(
        session.id,
        context.read<AuthProvider>().profile?.email ?? '',
      );
      if (session.isAcceptingAt(DateTime.now())) _runChecks();
    }
  }

  Future<void> _runChecks() async {
    await _checkGps();
    await _checkWifi();
  }

  Future<void> _checkGps() async {
    final session = _session;
    if (session == null) return;
    setState(() {
      _checkingGps = true;
      _gpsError = null;
    });
    try {
      final reading = await context.read<LocationService>().current();
      _gps = evaluateGps(
        classLat: session.latitude,
        classLng: session.longitude,
        radiusMeters: session.radiusMeters,
        lat: reading.latitude,
        lng: reading.longitude,
        accuracy: reading.accuracy,
        isMocked: reading.isMocked,
      );
    } on LocationException catch (e) {
      _gps = const GpsCheck(ok: false, issue: GpsIssue.unavailable);
      _gpsError = e;
    }
    if (mounted) setState(() => _checkingGps = false);
  }

  Future<void> _checkWifi() async {
    final session = _session;
    if (session == null) return;
    if (!session.wifiRequired) {
      setState(() => _wifi = const WifiCheck(ok: true));
      return;
    }
    setState(() => _checkingWifi = true);
    final bssid = await context.read<WifiService>().connectedBssid();
    _wifi = evaluateWifi(classBssids: session.bssids, studentBssid: bssid);
    if (mounted) setState(() => _checkingWifi = false);
  }

  bool get _checksDone =>
      !_checkingGps && !_checkingWifi && _gps != null && _wifi != null;

  Future<void> _scanAndSubmit() async {
    final session = _session!;
    setState(() => _error = null);
    final raw = await widget.scan(context);
    if (raw == null || !mounted) return;
    final payload = QrPayload.parse(raw);
    if (payload == null) {
      setState(() => _error = 'Ese código no es de SelvaCheck.');
      return;
    }
    if (payload.sessionId != session.id) {
      setState(() => _error = 'Ese código es de otra clase.');
      return;
    }

    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;
    final attendance = context.read<AttendanceRepository>();
    try {
      final enrollment = await context.read<CourseRepository>().getEnrollment(
        session.courseId,
        profile.email,
      );
      if (enrollment == null || !enrollment.isActive) {
        throw const MarkRejectedException();
      }
      await attendance.markAttendance(
        MarkRequest(
          session: session,
          enrollment: enrollment,
          uid: profile.uid,
          token: payload.token,
          gps: _gps!,
          wifi: _wifi!,
          deviceId: auth.device?.id ?? '',
        ),
      );
      if (mounted) {
        context.pushReplacement(Routes.attendanceResult(session.id));
      }
      return;
    } on AlreadyMarkedException {
      if (mounted) {
        context.pushReplacement(Routes.attendanceResult(session.id));
      }
      return;
    } on MarkRejectedException {
      _error = session.isAcceptingAt(DateTime.now())
          ? 'El código QR venció o no es válido. Vuelve a escanearlo.'
          : 'La ventana para marcar asistencia ya cerró.';
    } catch (e) {
      _error = AuthService.messageFor(e);
    }
    if (mounted) setState(() => _submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (session == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Clase no disponible',
          message: 'La clase no existe o ya no estás inscrito.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Marcar presente')),
      body: StreamBuilder<AttendanceRecord?>(
        stream: _myRecord,
        builder: (context, snap) {
          final record = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Header(session: session),
              const SizedBox(height: 12),
              _Countdown(session: session),
              const SizedBox(height: 16),
              if (record != null) ...[
                const MessageBanner(
                  'Ya registraste tu asistencia en esta clase.',
                  kind: BannerKind.success,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.pushReplacement(
                    Routes.attendanceResult(session.id),
                  ),
                  child: const Text('Ver mi registro'),
                ),
              ] else if (!session.isAcceptingAt(DateTime.now()))
                const MessageBanner(
                  'La ventana para marcar asistencia ya cerró.',
                )
              else
                ..._checks(session),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _checks(ClassSession session) {
    final text = Theme.of(context).textTheme;
    final gps = _gps;
    final wifi = _wifi;
    final needsReview = _checksDone && !(gps?.ok == true && wifi?.ok == true);
    final auth = context.watch<AuthProvider>();
    final binding = auth.deviceBinding;

    final done = [gps?.ok == true, wifi?.ok == true].where((v) => v).length;
    CheckState stateOf(bool loading, bool? ok) => loading
        ? CheckState.loading
        : ok == null
        ? CheckState.pending
        : ok
        ? CheckState.ok
        : CheckState.warning;

    return [
      Row(
        children: [
          Expanded(
            child: Text(
              'Validaciones de seguridad',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          StatusChip(
            label: '$done de 3 completas',
            foreground: AppColors.present,
            background: AppColors.presentContainer,
          ),
        ],
      ),
      const SizedBox(height: 10),
      ValidationTile(
        icon: Icons.my_location,
        title: 'Ubicación GPS',
        tag: switch (gps) {
          null => null,
          GpsCheck(ok: true) => 'Validado',
          _ => 'Revisar',
        },
        state: stateOf(_checkingGps, gps?.ok),
        description: _checkingGps
            ? 'Verificando…'
            : switch (gps) {
                null => 'Pendiente',
                GpsCheck(ok: true) =>
                  'Dentro del aula (${gps.distance!.round()} m · precisión '
                      '±${gps.accuracy!.round()} m).',
                GpsCheck(issue: GpsIssue.mocked) =>
                  'Se detectó una ubicación simulada.',
                GpsCheck(issue: GpsIssue.unavailable) =>
                  _gpsError?.message ?? 'No se pudo obtener la ubicación.',
                _ =>
                  'Estás a ${gps.distance!.round()} m del salón (radio '
                      '${session.radiusMeters} m, precisión '
                      '±${gps.accuracy!.round()} m).',
              },
        footer: _checkingGps
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (gps?.issue == GpsIssue.outOfRange &&
                      gps!.distance != null) ...[
                    const SizedBox(height: 4),
                    DistanceDiagram(
                      distance: gps.distance!,
                      radius: session.radiusMeters,
                      accuracy: gps.accuracy ?? 0,
                      room: session.room,
                    ),
                  ],
                  Wrap(
                    spacing: 4,
                    children: [
                      if (gps?.ok != true)
                        TextButton.icon(
                          onPressed: _checkGps,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reintentar'),
                        ),
                      if (_gpsError != null)
                        TextButton.icon(
                          onPressed: () => context
                              .read<LocationService>()
                              .openSettingsFor(_gpsError!.problem),
                          icon: const Icon(Icons.settings_outlined),
                          label: const Text('Ajustes'),
                        ),
                    ],
                  ),
                ],
              ),
      ),
      const SizedBox(height: 8),
      ValidationTile(
        icon: Icons.wifi,
        title: 'WiFi del aula',
        tag: wifi?.ok == true ? 'Validado' : null,
        state: stateOf(_checkingWifi, wifi?.ok),
        description: _checkingWifi
            ? 'Verificando…'
            : switch (wifi) {
                null => 'Pendiente',
                _ when !session.wifiRequired => 'No se exige en esta clase.',
                WifiCheck(ok: true) => 'Conectado a la red del aula.',
                WifiCheck(issue: WifiIssue.notConnected) =>
                  'No estás conectado a WiFi. Conéctate a la red del aula.',
                _ => 'Tu red WiFi no es la del aula.',
              },
        footer: !_checkingWifi && wifi?.ok == false
            ? TextButton.icon(
                onPressed: _checkWifi,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              )
            : null,
      ),
      const SizedBox(height: 8),
      const ValidationTile(
        icon: Icons.qr_code_2,
        title: 'Código QR de la clase',
        tag: 'Requerido',
        state: CheckState.pending,
        description:
            'Último paso: escanea el código que muestra tu docente. Cambia '
            'cada pocos segundos, así que regístrate apenas lo leas.',
      ),
      const SizedBox(height: 16),
      if (needsReview) ...[
        const MessageBanner(
          'Puedes registrarte igual, pero tu asistencia quedará "Por revisar" '
          'y tu docente decidirá. Si puedes, corrige la validación y '
          'reintenta.',
          kind: BannerKind.info,
        ),
        const SizedBox(height: 12),
      ],
      if (binding == DeviceBinding.otherDevice) ...[
        MessageBanner(
          'Tu cuenta está vinculada a otro teléfono'
          '${auth.profile?.deviceModel == null ? '' : ' (${auth.profile!.deviceModel})'}'
          '. Solo puedes marcar asistencia desde ese teléfono. Si lo '
          'cambiaste, pide a tu docente que desvincule tu cuenta.',
        ),
        const SizedBox(height: 12),
      ] else if (binding == DeviceBinding.unknown) ...[
        const MessageBanner(
          'Preparando la vinculación de tu cuenta con este teléfono…',
          kind: BannerKind.info,
        ),
        const SizedBox(height: 12),
      ],
      if (_error != null) ...[
        MessageBanner(_error!),
        const SizedBox(height: 12),
      ],
      LoadingButton(
        label: 'Escanear QR y registrar',
        icon: Icons.qr_code_scanner,
        loading: _submitting,
        onPressed: _checksDone && binding == DeviceBinding.thisDevice
            ? _scanAndSubmit
            : null,
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session});

  final ClassSession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget pill(IconData icon, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StatusChip(
              label: 'Sesión en curso',
              dot: true,
              foreground: AppColors.present,
              background: AppColors.presentContainer,
            ),
            const SizedBox(height: 8),
            Text(session.courseName, style: text.headlineSmall),
            if (session.teacherName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.school_outlined,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Prof. ${session.teacherName}',
                      style: text.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (session.room.isNotEmpty)
                  pill(Icons.meeting_room_outlined, session.room),
                pill(
                  Icons.schedule,
                  'Inició ${ScheduleFormat.clock(session.startedAt)}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Anillo con el tiempo que queda para marcar.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.session});

  final ClassSession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final presentLeft = session.presentDeadline.difference(now).inSeconds;
    final closeLeft = session.closesAt.difference(now).inSeconds;
    final presentTotal = session.presentDeadline
        .difference(session.startedAt)
        .inSeconds;
    final lateTotal = session.closesAt
        .difference(session.presentDeadline)
        .inSeconds;
    final (
      String time,
      String caption,
      Color color,
      double progress,
    ) = presentLeft > 0
        ? (
            Formatters.mmss(presentLeft),
            presentLeft <= 60 ? 'VENCE PRONTO' : 'PARA MARCAR PRESENTE',
            AppColors.primaryDark,
            presentTotal <= 0 ? 0.0 : presentLeft / presentTotal,
          )
        : closeLeft > 0
        ? (
            Formatters.mmss(closeLeft),
            'PARA MARCAR TARDE',
            AppColors.late,
            lateTotal <= 0 ? 0.0 : closeLeft / lateTotal,
          )
        : ('00:00', 'VENTANA CERRADA', AppColors.absent, 0.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        child: Column(
          children: [
            CountdownRing(
              progress: progress,
              time: time,
              caption: caption,
              color: color,
              size: 170,
            ),
            const SizedBox(height: 10),
            Text(
              'Tiempo restante para registrar tu asistencia presencial',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
