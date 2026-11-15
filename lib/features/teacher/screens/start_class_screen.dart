import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/attendance_checks.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/course.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/device_services.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../auth/providers/auth_provider.dart';

/// D4 · Iniciar clase. Toma la ubicación y las redes WiFi del teléfono del
/// docente, que serán la referencia para validar a los estudiantes.
class StartClassScreen extends StatefulWidget {
  const StartClassScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<StartClassScreen> createState() => _StartClassScreenState();
}

class _StartClassScreenState extends State<StartClassScreen> {
  Course? _course;
  List<String> _enrolledEmails = const [];
  List<ClassSession> _sessions = const [];
  String? _loadError;

  LocationReading? _location;
  LocationException? _locationError;
  bool _locating = false;

  List<String> _bssids = const [];
  String? _connectedBssid;
  bool _scanningWifi = false;

  late int _presentMinutes =
      context.read<AuthProvider>().profile?.defaultPresentMinutes ??
      AppConfig.presentWindow.inMinutes;
  bool _starting = false;

  /// Encuentro que se va a dictar (define el salón de la clase).
  CourseMeeting? _meeting;
  String? _startError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final courses = context.read<CourseRepository>();
    final attendance = context.read<AttendanceRepository>();
    try {
      final course = await courses.getCourse(widget.courseId);
      if (course == null) throw StateError('Curso no encontrado');
      final enrollments = await courses.getCourseEnrollments(widget.courseId);
      final sessions = await attendance.getCourseSessions(
        courseId: course.id,
        teacherId: course.teacherId,
      );
      if (!mounted) return;
      setState(() {
        _course = course;
        _meeting = course.meetingFor(DateTime.now());
        _enrolledEmails = enrollments
            .where((e) => e.isActive)
            .map((e) => e.email)
            .toList();
        _sessions = sessions;
      });
      if (_activeSession == null) await _detect();
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'No se pudo cargar el curso.');
      }
    }
  }

  ClassSession? get _activeSession {
    final now = DateTime.now();
    for (final s in _sessions) {
      if (s.isAcceptingAt(now)) return s;
    }
    return null;
  }

  /// Primero la ubicación (pide el permiso que también necesita el WiFi).
  Future<void> _detect() async {
    await _detectLocation();
    if (_location != null) await _detectWifi();
  }

  Future<void> _detectLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final reading = await context.read<LocationService>().current();
      if (mounted) setState(() => _location = reading);
    } on LocationException catch (e) {
      if (mounted) setState(() => _locationError = e);
    }
    if (mounted) setState(() => _locating = false);
  }

  Future<void> _detectWifi() async {
    setState(() => _scanningWifi = true);
    final wifi = context.read<WifiService>();
    final connected = await wifi.connectedBssid();
    final nearby = await wifi.nearbyBssids();
    if (!mounted) return;
    setState(() {
      _connectedBssid = normalizeBssid(connected);
      _bssids = {
        ?_connectedBssid,
        ...nearby.map(normalizeBssid).whereType<String>(),
      }.take(AppConfig.maxSessionBssids).toList();
      _scanningWifi = false;
    });
  }

  Future<void> _start() async {
    final course = _course!;
    final location = _location!;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmStartSheet(
        course: course,
        meeting: _meeting,
        enrolled: _enrolledEmails.length,
        location: location,
        wifiCount: _bssids.length,
        presentMinutes: _presentMinutes,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _starting = true;
      _startError = null;
    });
    final repo = context.read<AttendanceRepository>();
    try {
      // Cierra clases viejas que quedaron abiertas con la ventana vencida.
      for (final s in _sessions.where((s) => s.status == SessionStatus.open)) {
        await repo.closeSession(s);
      }
      final number =
          _sessions.fold(0, (max, s) => s.number > max ? s.number : max) + 1;
      final id = await repo.startSession(
        course: course,
        number: number,
        presentMinutes: _presentMinutes,
        lateMinutes: AppConfig.lateWindow.inMinutes,
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        bssids: _bssids,
        enrolledEmails: _enrolledEmails,
        room: _meeting?.locationLabel ?? course.locationLabel,
      );
      if (mounted) context.pushReplacement(Routes.liveClass(id));
    } catch (e) {
      if (mounted) {
        setState(() {
          _starting = false;
          _startError = AuthService.messageFor(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final course = _course;

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          title: _loadError!,
          message: 'Revisa tu conexión e inténtalo de nuevo.',
        ),
      );
    }
    if (course == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final active = _activeSession;
    final now = DateTime.now();
    final canStart =
        course.status == CourseStatus.active &&
        _location != null &&
        !_locating &&
        !_scanningWifi &&
        !_location!.isMocked;

    final reading = _location;
    final late = AppConfig.lateWindow.inMinutes;
    final gpsState = _locating
        ? CheckState.loading
        : _locationError != null || (reading?.isMocked ?? false)
        ? CheckState.failed
        : reading != null
        ? CheckState.ok
        : CheckState.pending;
    final wifiState = reading == null
        ? CheckState.pending
        : _scanningWifi
        ? CheckState.loading
        : _bssids.isEmpty
        ? CheckState.warning
        : CheckState.ok;

    return Scaffold(
      appBar: AppBar(title: const Text('Iniciar clase')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _HeaderCard(
            course: course,
            enrolled: _enrolledEmails.length,
            now: now,
            room: _meeting?.locationLabel ?? course.locationLabel,
            location: reading,
            locating: _locating,
            failed: gpsState == CheckState.failed,
          ),
          if (course.meetings.length > 1) ...[
            const SizedBox(height: 16),
            const FieldLabel('Encuentro'),
            PillSegments<CourseMeeting>(
              values: course.meetings,
              selected: _meeting ?? course.meetings.first,
              labelOf: (m) => m.timeLabel,
              onChanged: (m) => setState(() => _meeting = m),
            ),
          ],
          const SizedBox(height: 18),
          if (active != null) ...[
            const MessageBanner(
              'Ya hay una clase en curso para este curso.',
              kind: BannerKind.info,
            ),
            const SizedBox(height: 12),
            ActionBarButton(
              icon: Icons.sensors,
              label: 'Ir a la clase en curso',
              color: AppColors.present,
              onPressed: () =>
                  context.pushReplacement(Routes.liveClass(active.id)),
            ),
          ] else if (course.status != CourseStatus.active) ...[
            const MessageBanner(
              'Solo se puede iniciar clase en un curso publicado y habilitado.',
            ),
          ] else ...[
            const SectionTitle(
              'Validaciones de seguridad',
              trailing: '3 capas',
            ),
            ValidationTile(
              icon: Icons.my_location,
              title: 'Ubicación GPS',
              tag: 'Radio ${course.radiusMeters} m',
              description:
                  'Los estudiantes deben estar dentro del aula. La ubicación '
                  'se toma de tu teléfono: inicia la clase estando en el '
                  'salón.',
              state: gpsState,
              footer: _gpsFooter(context),
            ),
            const SizedBox(height: 8),
            ValidationTile(
              icon: Icons.qr_code_2,
              title: 'Código QR dinámico',
              tag: '${AppConfig.qrRotation.inSeconds} s',
              description:
                  'Proyéctalo o muéstralo desde tu teléfono; cambia solo '
                  'para que no se pueda reenviar.',
              state: CheckState.ok,
            ),
            const SizedBox(height: 8),
            ValidationTile(
              icon: Icons.wifi,
              title: 'WiFi del aula',
              tag: _bssids.isEmpty ? null : '${_bssids.length} redes',
              description: _wifiMessage(),
              state: wifiState,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Tolerancia para marcar presente',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                StatusChip(
                  label: '$_presentMinutes min',
                  foreground: AppColors.primaryDark,
                  background: AppColors.primaryContainer,
                ),
              ],
            ),
            const SizedBox(height: 10),
            PillSegments<int>(
              values: AppConfig.presentWindowOptions,
              selected: _presentMinutes,
              labelOf: (m) => '$m min',
              onChanged: (m) => setState(() => _presentMinutes = m),
            ),
            const SizedBox(height: 12),
            NoticeBox(
              title: 'Reglamento de asistencia',
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Durante los primeros '),
                    TextSpan(
                      text: '$_presentMinutes min',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const TextSpan(text: ' queda '),
                    const TextSpan(
                      text: 'Presente',
                      style: TextStyle(
                        color: AppColors.present,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(text: '; luego hay $late min para quedar '),
                    const TextSpan(
                      text: 'Tarde',
                      style: TextStyle(
                        color: AppColors.late,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '. Después, '),
                    const TextSpan(
                      text: 'Ausente',
                      style: TextStyle(
                        color: AppColors.absent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
            if (_startError != null) ...[
              const SizedBox(height: 12),
              MessageBanner(_startError!),
            ],
            const SizedBox(height: 20),
            LoadingButton(
              label: 'Iniciar clase ahora',
              icon: Icons.sensors,
              loading: _starting,
              onPressed: canStart ? _start : null,
            ),
          ],
        ],
      ),
    );
  }

  String _wifiMessage() {
    if (_location == null) return 'Se detecta después de obtener la ubicación.';
    if (_scanningWifi) return 'Buscando redes WiFi cercanas…';
    if (_bssids.isEmpty) {
      return 'No se detectaron redes: no se exigirá WiFi. Conéctate al WiFi '
          'del aula si quieres exigir esta validación.';
    }
    return _connectedBssid == null
        ? '${_bssids.length} redes cercanas registradas (no estás conectado '
              'a WiFi).'
        : 'Conectado al WiFi y ${_bssids.length} redes registradas.';
  }

  Widget? _gpsFooter(BuildContext context) {
    final reading = _location;
    final error = _locationError;
    if (_locating) return null;
    if (error != null || (reading?.isMocked ?? false)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MessageBanner(
            error?.message ??
                'Tu teléfono reporta una ubicación simulada. Desactiva las '
                    'apps de ubicación falsa para iniciar la clase.',
          ),
          Wrap(
            children: [
              TextButton.icon(
                onPressed: _detect,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
              if (error != null)
                TextButton.icon(
                  onPressed: () => context
                      .read<LocationService>()
                      .openSettingsFor(error.problem),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Abrir ajustes'),
                ),
            ],
          ),
        ],
      );
    }
    if (reading == null) return null;
    final low = reading.accuracy > 50;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: low ? AppColors.late : AppColors.present,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            low
                ? 'Precisión baja (±${reading.accuracy.round()} m): acércate '
                      'a una ventana y vuelve a medir.'
                : 'Precisión actual: ±${reading.accuracy.round()} m',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: low ? AppColors.tertiary : AppColors.present),
          ),
        ),
        InkWell(
          onTap: _detect,
          borderRadius: BorderRadius.circular(999),
          child: const Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.refresh, size: 18, color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}

/// Cabecera de D4: curso, fecha y estado de la ubicación del aula.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.course,
    required this.enrolled,
    required this.now,
    required this.room,
    required this.location,
    required this.locating,
    required this.failed,
  });

  final Course course;
  final int enrolled;
  final DateTime now;
  final String room;
  final LocationReading? location;
  final bool locating;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reading = location;
    final status = locating
        ? 'Obteniendo la ubicación del aula…'
        : failed
        ? 'No se pudo usar la ubicación'
        : reading != null
        ? 'Ubicación detectada · precisión ±${reading.accuracy.round()} m'
        : 'Ubicación pendiente';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            AppColors.surface,
            AppColors.primaryContainer.withValues(alpha: 0.35),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 6,
            spreadRadius: -1,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ESPACIO ACADÉMICO',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(course.name, style: text.headlineSmall),
                      const SizedBox(height: 6),
                      StatusChip(
                        label: '${course.group} · $enrolled inscritos',
                        foreground: AppColors.primaryDark,
                        background: AppColors.surfaceContainerHighest,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const IconBadge(
                  icon: Icons.co_present_outlined,
                  color: AppColors.primaryDark,
                  background: AppColors.surfaceVariant,
                  size: 48,
                ),
              ],
            ),
            const SizedBox(height: 12),
            InfoRow(
              icon: Icons.calendar_today_outlined,
              text:
                  '${ScheduleFormat.date(now)} · ${ScheduleFormat.clock(now)}',
            ),
            const SizedBox(height: 10),
            InsetPanel(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  IconBadge(
                    icon: Icons.location_on_outlined,
                    color: failed ? AppColors.absent : AppColors.present,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: text.labelSmall?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          room.isEmpty ? 'Sin salón' : room,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locating)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (reading != null && !failed)
                    const Icon(Icons.verified, color: AppColors.present),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// D4b · Confirmar inicio de clase.
class _ConfirmStartSheet extends StatelessWidget {
  const _ConfirmStartSheet({
    required this.course,
    required this.meeting,
    required this.enrolled,
    required this.location,
    required this.wifiCount,
    required this.presentMinutes,
  });

  final Course course;
  final CourseMeeting? meeting;
  final int enrolled;
  final LocationReading location;
  final int wifiCount;
  final int presentMinutes;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final late = AppConfig.lateWindow.inMinutes;
    Widget item(
      IconData icon,
      String title,
      String subtitle, {
      Widget? trailing,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          IconBadge(
            icon: icon,
            color: AppColors.primary,
            background: AppColors.surface,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  subtitle,
                  style: text.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('¿Iniciar la clase ahora?', style: text.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Se abrirá la ventana de asistencia para los estudiantes '
              'inscritos.',
              style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            InsetPanel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  item(
                    Icons.school_outlined,
                    '${course.name} · ${course.group}',
                    '$enrolled estudiantes inscritos · '
                        '${meeting?.label ?? course.locationLabel}',
                  ),
                  const Divider(height: 1),
                  item(
                    Icons.schedule,
                    'Ventana de tolerancia',
                    '$presentMinutes min para Presente + $late min para Tarde',
                    trailing: StatusChip(
                      label: '${presentMinutes + late} min total',
                      foreground: AppColors.tertiary,
                      background: AppColors.lateContainer,
                    ),
                  ),
                  const Divider(height: 1),
                  item(
                    Icons.qr_code_2,
                    'QR dinámico',
                    'Cambia cada ${AppConfig.qrRotation.inSeconds} s',
                    trailing: const StatusChip(
                      label: 'ACTIVO',
                      dot: true,
                      foreground: AppColors.present,
                      background: AppColors.surface,
                    ),
                  ),
                  const Divider(height: 1),
                  item(
                    Icons.my_location,
                    'GPS en rango ${course.radiusMeters} m',
                    'Precisión de tu teléfono: '
                        '±${location.accuracy.round()} m',
                  ),
                  const Divider(height: 1),
                  item(
                    Icons.wifi,
                    wifiCount == 0
                        ? 'WiFi no exigido'
                        : 'WiFi del aula · $wifiCount redes',
                    wifiCount == 0
                        ? 'No se detectaron redes al iniciar.'
                        : 'El estudiante debe estar conectado a una de ellas.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const NoticeBox(
              icon: Icons.info_outline,
              color: AppColors.textSecondary,
              background: AppColors.surfaceVariant,
              child: Text(
                'Se registrará la hora oficial del servidor de SelvaCheck. Los '
                'estudiantes verán la clase en vivo en su app.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Confirmar e iniciar clase'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surfaceVariant,
                foregroundColor: AppColors.textSecondary,
                shape: const StadiumBorder(),
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.tune),
              label: const Text('Volver y ajustar'),
            ),
          ],
        ),
      ),
    );
  }
}
