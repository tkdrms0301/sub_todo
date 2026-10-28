import 'package:flutter/material.dart';

import '../models/calendar_event.dart';

class ScheduledEvents extends StatelessWidget {
  const ScheduledEvents({
    required this.date,
    required this.events,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });
  final DateTime date;
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onEdit;
  final ValueChanged<CalendarEvent> onDelete;

  String _dateLabel(DateTime value) =>
      value.month.toString() + '월 ' + value.day.toString() + '일';

  @override
  Widget build(BuildContext context) {
    final matches = events.where((event) => event.includes(date)).toList()
      ..sort((a, b) => (a.startTime ?? '').compareTo(b.startTime ?? ''));
    if (matches.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Text(
            '일정',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        ...matches.map((event) {
          final occurrenceStart =
              event.occurrenceStartOn(date) ?? event.startDate;
          final occurrenceEnd = event.occurrenceEndOn(date) ?? event.endDate;
          final time = event.allDay
              ? '하루 종일'
              : event.startTime == null
              ? null
              : event.startTime! +
                    (event.endTime == null ? '' : ' – ' + event.endTime!);
          final range = occurrenceStart == occurrenceEnd
              ? _dateLabel(occurrenceStart)
              : _dateLabel(occurrenceStart) + ' – ' + _dateLabel(occurrenceEnd);
          final details =
              (event.gameName == null ? '' : event.gameName! + ' · ') +
              range +
              (time == null ? '' : ' · ' + time) +
              (event.repeatFrequency == null
                  ? ''
                  : ' · ' + event.repeatFrequency!.label + ' 반복');
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: const Color(0xFFFFF3E0),
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0xFFFFB74D), width: 1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFD180),
                child: Icon(
                  Icons.event_note_outlined,
                  color: Color(0xFF8D4B00),
                ),
              ),
              title: Text(
                event.title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(details),
                  if (event.memo != null) Text(event.memo!),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '일정 수정',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => onEdit(event),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '일정 삭제',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 36,
                      height: 36,
                    ),
                    padding: EdgeInsets.zero,
                    onPressed: () => onDelete(event),
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
              isThreeLine: event.memo != null,
            ),
          );
        }),
      ],
    );
  }
}
