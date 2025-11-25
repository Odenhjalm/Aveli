import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:aveli/features/studio/application/studio_providers.dart';
import 'package:aveli/features/studio/data/studio_sessions_repository.dart';
import 'package:aveli/shared/widgets/gradient_button.dart';
import 'package:aveli/widgets/glass_container.dart';

class StudioCalendar extends ConsumerWidget {
  const StudioCalendar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(teacherSessionsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sessioner & slots',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Planera dina livesändningar med månfas-kort och dra block för att skapa tider.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),
        GlassContainer(
          padding: const EdgeInsets.all(24),
          child: sessionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Kunde inte läsa sessioner: $error'),
            ),
            data: (sessions) => _CalendarGrid(sessions: sessions),
          ),
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatefulWidget {
  const _CalendarGrid({required this.sessions});

  final List<StudioSession> sessions;

  @override
  State<_CalendarGrid> createState() => _CalendarGridState();
}

class _CalendarGridState extends State<_CalendarGrid> {
  late DateTime _focusedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
  }

  void _changeMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _generateDays(_focusedMonth);
    final formatter = DateFormat.MMMM('sv_SE');
    final monthLabel =
        '${formatter.format(_focusedMonth)} ${_focusedMonth.year}'
            .toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                monthLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final day = days[index];
            final sessions = widget.sessions
                .where(
                  (session) =>
                      session.startAt != null &&
                      session.startAt!.year == day.year &&
                      session.startAt!.month == day.month &&
                      session.startAt!.day == day.day,
                )
                .toList(growable: false);
            return _CalendarDayCell(date: day, sessions: sessions);
          },
        ),
        const SizedBox(height: 16),
        GradientButton.icon(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Drag-and-drop-editor kommer i nästa sprint.'),
              ),
            );
          },
          label: const Text('Skapa ny session'),
        ),
      ],
    );
  }

  List<DateTime> _generateDays(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final totalCells = ((firstWeekday + daysInMonth) / 7).ceil() * 7;
    return List<DateTime>.generate(totalCells, (index) {
      final dayOffset = index - firstWeekday;
      return DateTime(month.year, month.month, dayOffset + 1);
    });
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({required this.date, required this.sessions});

  final DateTime date;
  final List<StudioSession> sessions;

  static const _moonPhases = [
    Icons.brightness_3_outlined,
    Icons.nightlight_round,
    Icons.bedtime,
    Icons.circle,
  ];

  Color _statusColor(BuildContext context) {
    if (sessions.any((s) => !s.isPublished)) {
      return Colors.amber;
    }
    if (sessions.isEmpty) {
      return Colors.white.withValues(alpha: 0.2);
    }
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentMonth = date.month == DateTime.now().month;
    final icon = _moonPhases[(date.day + date.month) % _moonPhases.length];
    final hasSessions = sessions.isNotEmpty;
    final badgeColor = _statusColor(context);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: hasSessions
          ? () => _showSessionSheet(context, sessions, date)
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
          gradient: hasSessions
              ? LinearGradient(
                  colors: [
                    badgeColor.withValues(alpha: 0.15),
                    badgeColor.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${date.day}',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isCurrentMonth
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                Icon(icon, size: 18, color: badgeColor),
              ],
            ),
            if (hasSessions) ...[
              const SizedBox(height: 8),
              for (final session in sessions.take(2))
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              if (sessions.length > 2)
                Text(
                  '+${sessions.length - 2} till',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ] else
              Expanded(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'Fri slot',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSessionSheet(
    BuildContext context,
    List<StudioSession> sessions,
    DateTime date,
  ) {
    final dateLabel = DateFormat('EEE d MMM', 'sv_SE').format(date);
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dateLabel,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              ...sessions.map(
                (session) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (session.description?.isNotEmpty == true)
                        Text(
                          session.description!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              session.isPublished ? 'Publicerad' : 'Utkast',
                            ),
                            backgroundColor: session.isPublished
                                ? Colors.green.withValues(alpha: 0.15)
                                : Colors.amber.withValues(alpha: 0.15),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(session.priceCents / 100).toStringAsFixed(2)} ${session.currency.toUpperCase()}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Stäng'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
