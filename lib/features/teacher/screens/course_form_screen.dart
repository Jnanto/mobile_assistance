import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/schedule_format.dart';
import '../../../data/models/course.dart';
import '../../../data/repositories/course_repository.dart';
import '../../../data/services/auth_service.dart';
import '../../../shared/widgets/common_widgets.dart';
import '../../../shared/widgets/form_widgets.dart';
import '../../../shared/widgets/visual_widgets.dart';
import '../../auth/providers/auth_provider.dart';

/// D2 · Crear curso, o editarlo si se pasa [courseId].
class CourseFormScreen extends StatelessWidget {
  const CourseFormScreen({super.key, this.courseId});

  final String? courseId;

  @override
  Widget build(BuildContext context) {
    if (courseId == null) return const _CourseForm();
    return StreamBuilder<Course?>(
      stream: context.read<CourseRepository>().watchCourse(courseId!),
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('No se pudo cargar el curso.')),
          );
        }
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return _CourseForm(initial: snap.data);
      },
    );
  }
}

class _CourseForm extends StatefulWidget {
  const _CourseForm({this.initial});

  final Course? initial;

  @override
  State<_CourseForm> createState() => _CourseFormState();
}

enum _CreateChoice { publish, draft }

class _CourseFormState extends State<_CourseForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _group;
  late String _period;
  late List<String> _periods;
  late final List<_MeetingDraft> _meetings;
  late double _radius;
  late int _color;
  bool _saving = false;
  String? _error;

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final c = widget.initial;
    _name = TextEditingController(text: c?.name);
    _code = TextEditingController(text: c?.code);
    _group = TextEditingController(text: c?.group ?? 'Grupo 1');
    _periods = ScheduleFormat.recentPeriods(DateTime.now());
    if (c != null && !_periods.contains(c.period)) _periods.add(c.period);
    _period = c?.period ?? _periods.first;
    _meetings = [
      for (final m in c?.meetings ?? const <CourseMeeting>[])
        _MeetingDraft.from(m),
    ];
    if (_meetings.isEmpty) _meetings.add(_MeetingDraft.blank());
    _radius = (c?.radiusMeters ?? 40).toDouble();
    _color = c?.colorIndex ?? 0;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _group.dispose();
    for (final m in _meetings) {
      m.dispose();
    }
    super.dispose();
  }

  Future<void> _pickTime(_MeetingDraft meeting, {required bool start}) async {
    final current = start ? meeting.start : meeting.end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    setState(() {
      final minutes = picked.hour * 60 + picked.minute;
      if (start) {
        meeting.start = minutes;
        // Mantiene la duración al mover el inicio después del fin.
        if (meeting.end <= minutes) meeting.end = minutes + 120;
      } else {
        meeting.end = minutes;
      }
    });
  }

  void _addMeeting() {
    final first = _meetings.first;
    setState(
      () => _meetings.add(
        _MeetingDraft.blank(
          day: first.day >= 5 ? 1 : first.day + 2,
          start: first.start,
          end: first.end,
          block: first.block.text,
          room: first.room.text,
        ),
      ),
    );
  }

  void _removeMeeting(_MeetingDraft meeting) {
    setState(() => _meetings.remove(meeting));
    meeting.dispose();
  }

  Course _buildCourse(CourseStatus status) {
    final profile = context.read<AuthProvider>().profile!;
    return Course(
      id: widget.initial?.id ?? '',
      name: _name.text.trim(),
      code: _code.text.trim().toUpperCase(),
      group: _group.text.trim(),
      period: _period,
      teacherId: profile.uid,
      teacherName: profile.name,
      meetings: [for (final m in _meetings) m.toMeeting()],
      radiusMeters: _radius.round(),
      colorIndex: _color,
      status: status,
    );
  }

  String? _validateSchedule() =>
      validateMeetings([for (final m in _meetings) m.toMeeting()]);

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState!.validate();
    final scheduleError = _validateSchedule();
    setState(() => _error = scheduleError);
    if (!formOk || scheduleError != null) return;

    final repo = context.read<CourseRepository>();
    if (_editing) {
      await _save(
        () => repo.updateCourse(_buildCourse(widget.initial!.status)),
      );
      if (mounted && _error == null) context.pop();
      return;
    }

    final draftCourse = _buildCourse(CourseStatus.draft);
    final choice = await showModalBottomSheet<_CreateChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmCreateSheet(course: draftCourse),
    );
    if (choice == null || !mounted) return;

    final status = choice == _CreateChoice.publish
        ? CourseStatus.active
        : CourseStatus.draft;
    String? newId;
    await _save(() async {
      newId = await repo.createCourse(_buildCourse(status));
    });
    if (mounted && newId != null) {
      context.pushReplacement(Routes.courseDetail(newId!));
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      _error = AuthService.messageFor(e);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Editar curso' : 'Crear curso')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _FormHero(editing: _editing),
              const SizedBox(height: 16),
              _Section(
                icon: Icons.assignment_outlined,
                title: 'Información general',
                children: [
                  const FieldLabel('Nombre de la asignatura'),
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.sentences,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Ingresa el nombre.' : null,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Inteligencia Artificial',
                      prefixIcon: Icon(Icons.book_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('Código'),
                            TextFormField(
                              controller: _code,
                              textCapitalization: TextCapitalization.characters,
                              validator: (v) => (v ?? '').trim().length > 20
                                  ? 'Máximo 20 caracteres.'
                                  : null,
                              decoration: const InputDecoration(
                                hintText: 'Ej. IS-502',
                                prefixIcon: Icon(Icons.tag),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const FieldLabel('Grupo'),
                            TextFormField(
                              controller: _group,
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Ingresa el grupo.'
                                  : null,
                              decoration: const InputDecoration(
                                hintText: 'Ej. Grupo 1',
                                prefixIcon: Icon(Icons.groups_outlined),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const FieldLabel('Periodo académico'),
                  DropdownButtonFormField<String>(
                    initialValue: _period,
                    isExpanded: true,
                    items: [
                      for (final p in _periods)
                        DropdownMenuItem(
                          value: p,
                          child: Text(p == _periods.first ? '$p (actual)' : p),
                        ),
                    ],
                    onChanged: (v) => setState(() => _period = v ?? _period),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ],
              ),
              _Section(
                icon: Icons.schedule,
                title: 'Encuentros semanales',
                trailing:
                    '${_meetings.length} '
                    '${_meetings.length == 1 ? 'encuentro' : 'encuentros'}/sem',
                children: [
                  for (var i = 0; i < _meetings.length; i++) ...[
                    if (i > 0) const Divider(height: 32),
                    _MeetingEditor(
                      index: i,
                      meeting: _meetings[i],
                      onChanged: () => setState(() {}),
                      onPickTime: (start) =>
                          _pickTime(_meetings[i], start: start),
                      onRemove: _meetings.length > 1
                          ? () => _removeMeeting(_meetings[i])
                          : null,
                    ),
                  ],
                  if (_meetings.length < AppConfig.maxMeetingsPerWeek) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _addMeeting,
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar encuentro'),
                    ),
                  ],
                  const SizedBox(height: 8),
                  FieldHint(
                    'Máximo ${AppConfig.maxMeetingsPerWeek} encuentros por '
                    'semana (límite de la universidad). Cada uno tiene su '
                    'propio horario y salón.',
                    icon: Icons.info_outline,
                  ),
                ],
              ),
              _Section(
                icon: Icons.share_location,
                title: 'Ubicación y perímetro GPS',
                trailing: '${_radius.round()} m',
                children: [
                  _PerimeterPreview(radius: _radius.round()),
                  const SizedBox(height: 14),
                  FieldLabel(
                    'Radio de cobertura',
                    trailing: '${_radius.round()} m',
                    trailingColor: AppColors.primaryDark,
                  ),
                  Slider(
                    value: _radius,
                    min: 20,
                    max: 100,
                    divisions: 16,
                    label: '${_radius.round()} m',
                    onChanged: (v) => setState(() => _radius = v),
                  ),
                  Row(
                    children: [
                      Text(
                        '20 m',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _radius.round() == 40
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              size: 14,
                              color: AppColors.present,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _radius.round() == 40
                                    ? 'Recomendado para aulas estándar'
                                    : 'Se recomiendan 40 m',
                                overflow: TextOverflow.ellipsis,
                                style: text.labelSmall?.copyWith(
                                  color: AppColors.present,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '100 m',
                        style: text.labelSmall?.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              _Section(
                icon: Icons.palette_outlined,
                title: 'Color de la tarjeta',
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < AppColors.courseColors.length; i++)
                        Semantics(
                          selected: _color == i,
                          button: true,
                          label: 'Color ${i + 1}',
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => _color = i),
                            child: Container(
                              width: 44,
                              height: 44,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _color == i
                                      ? AppColors.courseColors[i]
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.courseColors[i],
                                  shape: BoxShape.circle,
                                ),
                                child: _color == i
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 20,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (_error != null) ...[
                MessageBanner(_error!),
                const SizedBox(height: 16),
              ],
              LoadingButton(
                label: _editing ? 'Guardar cambios' : 'Guardar curso',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _submit,
              ),
              if (!_editing) ...[
                const SizedBox(height: 10),
                FieldHint(
                  'Después de guardarlo podrás inscribir a tus estudiantes '
                  'desde "Estudiantes" en el detalle del curso.',
                  icon: Icons.person_add_alt,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, color: AppColors.primaryDark, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (trailing != null)
                    StatusChip(
                      label: trailing!,
                      foreground: AppColors.present,
                      background: AppColors.presentContainer,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(label),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.access_time),
            ),
            child: Text(value),
          ),
        ),
      ],
    );
  }
}

/// D2b · Confirmar creación del curso.
class _ConfirmCreateSheet extends StatelessWidget {
  const _ConfirmCreateSheet({required this.course});

  final Course course;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget row(IconData icon, String title, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InsetPanel(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(
              icon: icon,
              color: AppColors.textSecondary,
              background: AppColors.surface,
              size: 38,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.labelSmall?.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  value,
                ],
              ),
            ),
          ],
        ),
      ),
    );
    Text strong(String value) => Text(
      value,
      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(
                  icon: Icons.rocket_launch_outlined,
                  color: AppColors.primaryDark,
                  background: AppColors.primaryContainer,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Publicar y activar el curso?',
                        style: text.headlineSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Una vez publicado, los estudiantes que agregues '
                        'podrán verlo en su app.',
                        style: text.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            row(
              Icons.book_outlined,
              'Asignatura',
              strong(
                [
                  course.name,
                  course.code,
                  course.group,
                ].where((s) => s.isNotEmpty).join(' · '),
              ),
            ),
            row(
              Icons.schedule,
              'Horario semanal',
              strong(course.meetings.map((m) => m.timeLabel).join(' · ')),
            ),
            row(
              Icons.meeting_room_outlined,
              'Ubicación',
              strong(
                course.locationLabel.isEmpty
                    ? 'Sin salón'
                    : course.locationLabel,
              ),
            ),
            row(
              Icons.verified_user_outlined,
              'Validaciones de asistencia · Activas',
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  StatusChip(
                    label: 'Geocerca GPS (${course.radiusMeters} m)',
                    icon: Icons.my_location,
                    foreground: AppColors.present,
                    background: AppColors.presentContainer,
                  ),
                  StatusChip(
                    label: 'QR dinámico (${AppConfig.qrRotation.inSeconds} s)',
                    icon: Icons.sync,
                    foreground: AppColors.present,
                    background: AppColors.presentContainer,
                  ),
                  const StatusChip(
                    label: 'WiFi del aula',
                    icon: Icons.wifi,
                    foreground: AppColors.present,
                    background: AppColors.presentContainer,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(context, _CreateChoice.publish),
              icon: const Icon(Icons.rocket_launch_outlined),
              label: const Text('Sí, publicar y activar curso'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.surfaceVariant,
                foregroundColor: AppColors.textPrimary,
                shape: const StadiumBorder(),
              ),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.edit_note),
              label: const Text('Revisar o editar datos'),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
              onPressed: () => Navigator.pop(context, _CreateChoice.draft),
              icon: const Icon(Icons.bookmark_border),
              label: const Text('Guardar solo como borrador'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cabecera verde del formulario.
class _FormHero extends StatelessWidget {
  const _FormHero({required this.editing});

  final bool editing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7D32), AppColors.primaryDark],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -8,
            top: -8,
            child: Icon(
              Icons.dashboard_customize_outlined,
              size: 96,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusChip(
                  label: 'Gestión académica',
                  icon: Icons.school_outlined,
                  foreground: Colors.white,
                  background: Colors.white.withValues(alpha: 0.15),
                ),
                const SizedBox(height: 8),
                Text(
                  editing ? 'Editar curso' : 'Crear nuevo curso o asignatura',
                  style: text.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configura los encuentros, el salón y el perímetro para '
                  'el registro de asistencia.',
                  style: text.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Esquema del perímetro: círculo del radio con el aula en el centro. La
/// ubicación real se toma del teléfono del docente al iniciar cada clase.
class _PerimeterPreview extends StatelessWidget {
  const _PerimeterPreview({required this.radius});

  final int radius;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = 60 + (radius - 20) * 1.1;
    return Container(
      height: 170,
      decoration: BoxDecoration(
        color: AppColors.presentContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.present.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.present.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppColors.primaryDark,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.location_on, color: Colors.white),
          ),
          Positioned(
            left: 10,
            right: 10,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.my_location,
                    size: 14,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Centro: tu ubicación al iniciar la clase',
                      overflow: TextOverflow.ellipsis,
                      style: text.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Encuentro en edición: día, horario y salón.
class _MeetingDraft {
  _MeetingDraft({
    required this.day,
    required this.start,
    required this.end,
    required String block,
    required String room,
  }) : block = TextEditingController(text: block),
       room = TextEditingController(text: room);

  factory _MeetingDraft.from(CourseMeeting m) => _MeetingDraft(
    day: m.day,
    start: m.startMinutes,
    end: m.endMinutes,
    block: m.block,
    room: m.room,
  );

  factory _MeetingDraft.blank({
    int day = 1,
    int start = 14 * 60,
    int end = 16 * 60,
    String block = '',
    String room = '',
  }) =>
      _MeetingDraft(day: day, start: start, end: end, block: block, room: room);

  int day;
  int start;
  int end;
  final TextEditingController block;
  final TextEditingController room;

  CourseMeeting toMeeting() => CourseMeeting(
    day: day,
    startMinutes: start,
    endMinutes: end,
    block: block.text.trim(),
    room: room.text.trim(),
  );

  void dispose() {
    block.dispose();
    room.dispose();
  }
}

class _MeetingEditor extends StatelessWidget {
  const _MeetingEditor({
    required this.index,
    required this.meeting,
    required this.onChanged,
    required this.onPickTime,
    required this.onRemove,
  });

  final int index;
  final _MeetingDraft meeting;
  final VoidCallback onChanged;
  final void Function(bool start) onPickTime;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Encuentro ${index + 1}', style: text.titleSmall),
            ),
            if (onRemove != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.absent),
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Quitar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const FieldLabel('Día'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final entry in ScheduleFormat.dayLetters.entries)
              Tooltip(
                message: ScheduleFormat.days([entry.key]),
                child: Semantics(
                  selected: meeting.day == entry.key,
                  button: true,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      meeting.day = entry.key;
                      onChanged();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: meeting.day == entry.key
                            ? AppColors.primaryDark
                            : AppColors.surfaceVariant,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        entry.value,
                        style: text.titleSmall?.copyWith(
                          color: meeting.day == entry.key
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _TimeField(
                label: 'Inicio',
                value: ScheduleFormat.time(meeting.start),
                onTap: () => onPickTime(true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TimeField(
                label: 'Fin',
                value: ScheduleFormat.time(meeting.end),
                onTap: () => onPickTime(false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Bloque'),
                  TextFormField(
                    controller: meeting.block,
                    decoration: const InputDecoration(
                      hintText: 'Ej. Bloque 7',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldLabel('Salón'),
                  TextFormField(
                    controller: meeting.room,
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Ingresa el salón.'
                        : ((v ?? '').trim().length > 40
                              ? 'Máximo 40 caracteres.'
                              : null),
                    decoration: const InputDecoration(
                      hintText: 'Ej. Salón 7205',
                      prefixIcon: Icon(Icons.meeting_room_outlined),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
