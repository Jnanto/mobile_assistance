import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/attendance_checks.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/attendance_record.dart';
import '../../../data/models/class_session.dart';
import '../../../data/models/enrollment.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../auth/providers/session_controller.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../widgets/manual_status_sheet.dart';

/// D5 · Clase en vivo: QR dinámico, registros en tiempo real y revisión.
class LiveClassScreen extends StatefulWidget {
  const LiveClassScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<LiveClassScreen> createState() => _LiveClassScreenState();
}

class _LiveClassScreenState extends State<LiveClassScreen> {
  late final AttendanceRepository _repo;
  StreamSubscription<ClassSession?>? _sessionSub;
  ClassSession? _session;
  bool _loaded = false;

  Stream<List<AttendanceRecord>>? _records;
  Stream<List<Enrollment>>? _enrollments;
  List<String> _roster = const [];

  /// QR mostrado. Solo cambia cuando el servidor ya tiene el token nuevo.
  final _payload = ValueNotifier<String?>(null);
  String _token = '';
  DateTime? _rotatedAt;
  bool _rotating = false;
  bool _tokenFailing = false;
  Timer? _rotationTimer;
  Timer? _ticker;

  /// Libera la sesión de la app, que se mantiene abierta mientras se
  /// proyecta el QR (el docente puede pasar más de 10 min sin tocar).
  VoidCallback? _releaseSession;

  @override
  void initState() {
    super.initState();
    _repo = context.read<AttendanceRepository>();
    _sessionSub = _repo.watchSession(widget.sessionId).listen(_onSession);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _releaseSession = context.read<SessionController>().hold();
    _setWakelock(true);
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _rotationTimer?.cancel();
    _ticker?.cancel();
    _payload.dispose();
    _releaseSession?.call();
    _setWakelock(false);
    super.dispose();
  }

  /// Mantiene la pantalla encendida mientras se proyecta el QR.
  Future<void> _setWakelock(bool on) async {
    try {
      await (on ? WakelockPlus.enable() : WakelockPlus.disable());
    } catch (_) {
      // Sin soporte (por ejemplo, en pruebas): no es crítico.
    }
  }

  void _onSession(ClassSession? session) {
    final first = !_loaded;
    setState(() {
      _session = session;
      _loaded = true;
    });
    if (session == null) return;
    if (first) {
      _records = _repo.watchSessionRecords(
        sessionId: session.id,
        courseId: session.courseId,
      );
      _enrollments = context.read<CourseRepository>().watchCourseEnrollments(
        session.courseId,
      );
      _repo.getSessionRoster(session.id).then((emails) {
        if (mounted) setState(() => _roster = emails);
      }, onError: (Object _) {});
    }
    _syncRotation();
  }

  bool get _accepting => _session?.isAcceptingAt(DateTime.now()) ?? false;

  void _syncRotation() {
    if (_accepting) {
      if (_rotationTimer == null) {
        _rotate();
        _rotationTimer = Timer.periodic(AppConfig.qrRotation, (_) => _rotate());
      }
    } else {
      _rotationTimer?.cancel();
      _rotationTimer = null;
      _payload.value = null;
    }
  }

  Future<void> _rotate() async {
    if (_rotating || !_accepting) return;
    _rotating = true;
    final next = QrPayload.newToken();
    try {
      await _repo.rotateToken(
        sessionId: widget.sessionId,
        token: next,
        previous: _token,
      );
      _token = next;
      _rotatedAt = DateTime.now();
      _payload.value = QrPayload(widget.sessionId, next).encode();
      if (mounted) setState(() => _tokenFailing = false);
    } catch (_) {
      if (mounted) setState(() => _tokenFailing = true);
    }
    _rotating = false;
  }

  void _tick() {
    if (!mounted) return;
    if (_rotationTimer != null && !_accepting) _syncRotation();
    setState(() {});
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Cerrar la asistencia?'),
        content: const Text(
          'Los estudiantes que no hayan marcado quedarán como "Ausente".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar asistencia'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.closeSession(_session!);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.messageFor(e))),
      );
    }
  }

  Future<void> _review(AttendanceRecord record, bool approve) async {
    final session = _session!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.reviewRecord(
        session: session,
        email: record.email,
        teacherId: session.teacherId,
        approve: approve,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AuthService.messageFor(e))),
      );
    }
  }

  void _showFullScreen() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _session?.courseName ?? '',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<String?>(
                        valueListenable: _payload,
                        builder: (context, payload, _) => payload == null
                            ? const Text('El código no está disponible.')
                            : _QrBox(payload: payload, size: 320),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Escanea este código desde SelvaCheck para registrar '
                        'tu asistencia.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: 'Cerrar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
          title: 'Clase no encontrada',
          message: 'Es posible que ya no exista.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(session.courseName, overflow: TextOverflow.ellipsis),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.school_outlined,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Clase #${session.number} · ${session.room}',
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<Enrollment>>(
        stream: _enrollments,
        builder: (context, enrollmentSnap) =>
            StreamBuilder<List<AttendanceRecord>>(
              stream: _records,
              builder: (context, recordSnap) => _buildBody(
                session,
                recordSnap.data ?? const [],
                enrollmentSnap.data ?? const [],
              ),
            ),
      ),
    );
  }

  Widget _buildBody(
    ClassSession session,
    List<AttendanceRecord> records,
    List<Enrollment> enrollments,
  ) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final accepting = session.isAcceptingAt(now);

    final sorted = [...records]
      ..sort((a, b) => (b.markedAt ?? now).compareTo(a.markedAt ?? now));
    int count(AttendanceStatus s) =>
        records.where((r) => r.statusFor(session) == s).length;
    final marked = records.map((r) => r.email).toSet();
    final names = {for (final e in enrollments) e.email: e.name};
    final byEmail = {for (final e in enrollments) e.email: e};
    final pending = _roster.where((e) => !marked.contains(e)).toList()
      ..sort((a, b) => (names[a] ?? a).compareTo(names[b] ?? b));
    final total = _roster.isEmpty ? records.length : _roster.length;

    final present = count(AttendanceStatus.present);
    final late = count(AttendanceStatus.late);
    final review = count(AttendanceStatus.review);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _WindowCard(session: session, now: now),
        const SizedBox(height: 12),
        _ProgressCard(
          registered: records.length,
          total: total,
          present: present,
          late: late,
          review: review,
          pending: pending.length,
          accepting: accepting,
        ),
        const SizedBox(height: 12),
        if (accepting) _qrCard(text),
        if (accepting) const SizedBox(height: 16),
        Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Icon(
                Icons.fact_check_outlined,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SectionTitle(
                'Registros en tiempo real',
                count: '${records.length}',
              ),
            ),
          ],
        ),
        if (records.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'Aún nadie ha marcado',
              message: 'Los registros aparecerán aquí al instante.',
            ),
          ),
        for (final record in sorted) ...[
          _RecordTile(
            record: record,
            session: session,
            onApprove: () => _review(record, true),
            onReject: () => _review(record, false),
          ),
          const SizedBox(height: 8),
        ],
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 4),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              shape: const Border(),
              leading: const Icon(
                Icons.hourglass_empty,
                color: AppColors.textSecondary,
              ),
              title: Text(
                accepting
                    ? 'Pendientes por marcar (${pending.length})'
                    : 'Sin registro: Ausentes (${pending.length})',
                style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              children: [
                for (final email in pending)
                  ListTile(
                    leading: _Initials(
                      name: names[email] ?? email,
                      email: email,
                    ),
                    title: Text(names[email] ?? email, style: text.titleSmall),
                    subtitle: Text(
                      accepting ? 'En espera' : 'Sin registro',
                      style: text.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                    trailing: byEmail[email] == null
                        ? null
                        : TextButton(
                            onPressed: () => showManualStatusSheet(
                              context,
                              session: session,
                              enrollment: byEmail[email]!,
                              current: accepting
                                  ? null
                                  : AttendanceStatus.absent,
                              initial: AttendanceStatus.present,
                              suggestedReason: 'Marcado manual en clase',
                            ),
                            child: const Text('Marcar'),
                          ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        if (session.status == SessionStatus.open) ...[
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.absent,
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.absentContainer),
            ),
            onPressed: _close,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Cerrar asistencia ahora'),
          ),
          const SizedBox(height: 8),
          Text.rich(
            const TextSpan(
              children: [
                TextSpan(text: 'Los estudiantes pendientes quedarán como '),
                TextSpan(
                  text: 'Ausente',
                  style: TextStyle(
                    color: AppColors.absent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '.'),
              ],
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ] else
          MessageBanner(
            'Asistencia cerrada'
            '${session.closedAt == null ? '' : ' a las ${ScheduleFormat.clock(session.closedAt!)}'}'
            '.',
            kind: BannerKind.info,
          ),
      ],
    );
  }

  Widget _qrCard(TextTheme text) {
    final rotatedAt = _rotatedAt;
    final elapsed = rotatedAt == null
        ? 0
        : DateTime.now().difference(rotatedAt).inSeconds;
    final remaining = (AppConfig.qrRotation.inSeconds - elapsed).clamp(
      0,
      AppConfig.qrRotation.inSeconds,
    );
    final cycle = AppConfig.qrRotation.inSeconds;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.presentContainer,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: AppColors.present,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Código dinámico',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Seguridad antifraude',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                StatusChip(
                  label: 'Cambia en ${remaining}s',
                  icon: Icons.sync,
                  foreground: AppColors.textSecondary,
                  background: AppColors.surfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: ValueListenableBuilder<String?>(
                valueListenable: _payload,
                builder: (context, payload, _) => payload == null
                    ? const SizedBox(
                        height: 220,
                        child: Center(child: Text('Generando código…')),
                      )
                    : _QrBox(payload: payload, size: 220),
              ),
            ),
            if (_tokenFailing) ...[
              const SizedBox(height: 12),
              const MessageBanner(
                'Sin conexión: el código no se está renovando y los '
                'estudiantes no podrán marcar.',
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: remaining / cycle,
                minHeight: 6,
                color: AppColors.primaryDark,
                backgroundColor: AppColors.surfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rotación automática',
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Text(
                  'Ciclo: $cycle segundos',
                  style: text.labelSmall?.copyWith(color: AppColors.textMuted),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
              ),
              onPressed: _showFullScreen,
              icon: const Icon(Icons.fullscreen),
              label: const Text('Proyectar en pantalla completa'),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrBox extends StatelessWidget {
  const _QrBox({required this.payload, required this.size});

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: payload,
      size: size,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: AppColors.primaryDark,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: AppColors.primaryDark,
      ),
    );
  }
}

/// Cuenta regresiva de la ventana para marcar, en un anillo.
class _WindowCard extends StatelessWidget {
  const _WindowCard({required this.session, required this.now});

  final ClassSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final String time;
    final String caption;
    final Color color;
    final double progress;
    final presentTotal = session.presentDeadline
        .difference(session.startedAt)
        .inSeconds;
    final lateTotal = session.closesAt
        .difference(session.presentDeadline)
        .inSeconds;
    if (session.status == SessionStatus.closed) {
      time = 'Cerrada';
      caption = 'ASISTENCIA CERRADA';
      color = AppColors.textSecondary;
      progress = 0;
    } else if (now.isBefore(session.presentDeadline)) {
      final left = session.presentDeadline.difference(now).inSeconds;
      time = Formatters.mmss(left);
      caption = 'PARA MARCAR PRESENTE';
      color = AppColors.primaryDark;
      progress = presentTotal <= 0 ? 0 : left / presentTotal;
    } else if (now.isBefore(session.closesAt)) {
      final left = session.closesAt.difference(now).inSeconds;
      time = Formatters.mmss(left);
      caption = 'PARA MARCAR TARDE';
      color = AppColors.late;
      progress = lateTotal <= 0 ? 0 : left / lateTotal;
    } else {
      time = '00:00';
      caption = 'VENTANA CERRADA';
      color = AppColors.absent;
      progress = 0;
    }
    final open =
        session.status == SessionStatus.open && now.isBefore(session.closesAt);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.presentContainer.withValues(alpha: 0.6),
            AppColors.surface,
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 6,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            CountdownRing(
              progress: progress,
              time: time,
              caption: caption,
              color: color,
              size: 190,
              footer: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    open ? Icons.lock_clock : Icons.lock_outline,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      open ? 'Tolerancia activa' : 'Sin marcas nuevas',
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Inició ${ScheduleFormat.clock(session.startedAt)}',
              style: text.bodySmall?.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avance del registro: cuántos marcaron y en qué estado.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.registered,
    required this.total,
    required this.present,
    required this.late,
    required this.review,
    required this.pending,
    required this.accepting,
  });

  final int registered;
  final int total;
  final int present;
  final int late;
  final int review;
  final int pending;
  final bool accepting;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rate = total == 0 ? 0.0 : registered / total;
    Widget bar(int value, Color color) => value == 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: value,
            child: Container(color: color),
          );
    Widget pill(String label, int value, Color fg, Color bg) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: text.titleMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconBadge(
                  icon: Icons.how_to_reg_outlined,
                  color: AppColors.present,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Asistencia en aula',
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Se actualiza en tiempo real',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$registered de $total registrados',
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${(rate * 100).round()} % registrado',
                      style: text.labelSmall?.copyWith(
                        color: AppColors.present,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    bar(present, AppColors.present),
                    bar(late, AppColors.late),
                    bar(review, AppColors.reviewChart),
                    bar(
                      pending + (total - registered - pending).clamp(0, total),
                      AppColors.surfaceVariant,
                    ),
                    if (total == 0)
                      Expanded(
                        child: Container(color: AppColors.surfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                pill(
                  'Presentes',
                  present,
                  AppColors.present,
                  AppColors.presentContainer,
                ),
                const SizedBox(width: 6),
                pill(
                  'Tarde',
                  late,
                  AppColors.tertiary,
                  AppColors.lateContainer,
                ),
                const SizedBox(width: 6),
                pill(
                  'Por revisar',
                  review,
                  AppColors.review,
                  AppColors.reviewContainer,
                ),
                const SizedBox(width: 6),
                pill(
                  accepting ? 'Pendientes' : 'Ausentes',
                  pending,
                  AppColors.textSecondary,
                  AppColors.surfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Foto o iniciales de un estudiante, en un círculo gris.
class _Initials extends StatelessWidget {
  const _Initials({required this.name, this.email});

  final String name;
  final String? email;

  @override
  Widget build(BuildContext context) => PhotoOrInitials(
    name: name,
    email: email,
    background: AppColors.surfaceVariant,
    foreground: AppColors.textSecondary,
  );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({
    required this.record,
    required this.session,
    required this.onApprove,
    required this.onReject,
  });

  final AttendanceRecord record;
  final ClassSession session;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = record.statusFor(session);
    final markedAt = record.markedAt;
    final timing = attendanceStyle(record.timingStatus(session)).label;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Initials(name: record.name, email: record.email),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.name,
                        style: text.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '#${record.studentCode}',
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.schedule,
                            size: 12,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              markedAt == null
                                  ? 'enviando…'
                                  : ScheduleFormat.clock(markedAt),
                              overflow: TextOverflow.ellipsis,
                              style: text.labelSmall?.copyWith(
                                color: AppColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                AttendanceChip(status: status),
              ],
            ),
            if (record.review != ReviewStatus.notRequired &&
                record.reviewReasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              InsetPanel(
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.review,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.reviewReasons.join(' · '),
                        style: text.bodySmall?.copyWith(
                          color: AppColors.review,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (record.review == ReviewStatus.pending) ...[
              const SizedBox(height: 8),
              Text(
                'Si apruebas, quedará como $timing.',
                style: text.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.absent,
                        side: const BorderSide(color: AppColors.absent),
                        minimumSize: const Size.fromHeight(40),
                      ),
                      onPressed: onReject,
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                      ),
                      onPressed: onApprove,
                      child: const Text('Aprobar'),
                    ),
                  ),
                ],
              ),
            ] else if (record.review == ReviewStatus.approved ||
                record.review == ReviewStatus.rejected) ...[
              const SizedBox(height: 4),
              Text(
                record.review == ReviewStatus.approved
                    ? 'Aprobada por ti'
                    : 'Rechazada por ti',
                style: text.bodySmall?.copyWith(color: AppColors.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
