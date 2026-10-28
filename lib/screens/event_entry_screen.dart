import 'package:flutter/material.dart';

import '../models/calendar_event.dart';

class EventEntryScreen extends StatefulWidget {
  const EventEntryScreen({
    required this.initialDate,
    required this.gameNames,
    this.initialEvent,
    super.key,
  });
  final DateTime initialDate;
  final List<String> gameNames;
  final CalendarEvent? initialEvent;

  @override
  State<EventEntryScreen> createState() => _EventEntryScreenState();
}

class _EventEntryScreenState extends State<EventEntryScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _memoController;
  late DateTime _startDate;
  late DateTime _endDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 13, minute: 0);
  bool _allDay = false;
  String _selectedGame = _generalSchedule;
  EventRepeatFrequency? _repeatFrequency;
  DateTime? _repeatUntil;

  @override
  void initState() {
    super.initState();
    final event = widget.initialEvent;
    _titleController = TextEditingController(text: event?.title ?? '');
    _memoController = TextEditingController(text: event?.memo ?? '');
    _startDate =
        event?.startDate ??
        DateTime(
          widget.initialDate.year,
          widget.initialDate.month,
          widget.initialDate.day,
        );
    _endDate = event?.endDate ?? _startDate;
    _allDay = event?.allDay ?? false;
    _selectedGame =
        event?.gameName != null && widget.gameNames.contains(event!.gameName)
        ? event.gameName!
        : _generalSchedule;
    _repeatFrequency = event?.repeatFrequency;
    _repeatUntil = event?.repeatUntil;
    _startTime = _parseTime(
      event?.startTime,
      const TimeOfDay(hour: 12, minute: 0),
    );
    _endTime = _parseTime(event?.endTime, const TimeOfDay(hour: 13, minute: 0));
  }

  TimeOfDay _parseTime(String? value, TimeOfDay fallback) {
    if (value == null) return fallback;
    final parts = value.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  String _dateLabel(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return date.month.toString() +
        '월 ' +
        date.day.toString() +
        '일 (' +
        weekdays[date.weekday - 1] +
        ')';
  }

  String _timeLabel(TimeOfDay time) => time.format(context);

  Future<void> _pickDate({required bool start}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
        if (_repeatUntil != null && _repeatUntil!.isBefore(_startDate)) {
          _repeatUntil = null;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) _startDate = _endDate;
      }
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: start ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _pickRepeatUntil() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatUntil ?? _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
      helpText: '마지막 반복 날짜 선택',
    );
    if (picked != null) {
      setState(
        () => _repeatUntil = DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  void _save() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('제목을 입력해 주세요.')));
      return;
    }
    Navigator.pop(
      context,
      CalendarEvent(
        gameName: _selectedGame == _generalSchedule ? null : _selectedGame,
        title: title,
        startDate: _startDate,
        endDate: _endDate,
        startTime: _allDay ? null : _timeValue(_startTime),
        endTime: _allDay ? null : _timeValue(_endTime),
        memo: _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
        allDay: _allDay,
        repeatFrequency: _repeatFrequency,
        repeatUntil: _repeatFrequency == null ? null : _repeatUntil,
      ),
    );
  }

  String _timeValue(TimeOfDay value) =>
      value.hour.toString().padLeft(2, '0') +
      ':' +
      value.minute.toString().padLeft(2, '0');

  Widget _divider() =>
      Divider(height: 1, thickness: 1, color: const Color(0xFFE5E7EF));

  Widget _dateTimeCell({required bool start}) {
    final date = start ? _startDate : _endDate;
    final time = start ? _startTime : _endTime;
    return Expanded(
      child: Column(
        children: [
          TextButton(
            onPressed: () => _pickDate(start: start),
            child: Text(
              _dateLabel(date),
              style: const TextStyle(fontSize: 15, color: Color(0xFF252B40)),
            ),
          ),
          if (!_allDay)
            TextButton(
              onPressed: () => _pickTime(start: start),
              child: Text(
                _timeLabel(time),
                style: const TextStyle(fontSize: 15, color: Color(0xFF252B40)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF485CCB);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF6F7FB),
        surfaceTintColor: Colors.transparent,
        title: Text(widget.initialEvent == null ? '일정 추가' : '일정 수정'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFE9ECF8),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Row(
                  children: [
                    Expanded(child: _TopTab(label: '일정', selected: true)),
                    Expanded(child: _TopTab(label: '리마인더', selected: false)),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _titleController,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: '제목',
                          suffixIcon: const Icon(
                            Icons.palette_outlined,
                            color: accent,
                          ),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: accent.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _selectedGame,
                        decoration: const InputDecoration(
                          labelText: '게임 / 일정 분류',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: _generalSchedule,
                            child: Text('일반 일정'),
                          ),
                          ...widget.gameNames.map(
                            (name) => DropdownMenuItem(
                              value: name,
                              child: Text(name),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null)
                            setState(() => _selectedGame = value);
                        },
                      ),

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.access_time, color: accent),
                        title: const Text('하루 종일'),
                        value: _allDay,
                        onChanged: (value) => setState(() => _allDay = value),
                      ),
                      Row(
                        children: [
                          _dateTimeCell(start: true),
                          const Icon(Icons.arrow_forward, color: accent),
                          _dateTimeCell(start: false),
                        ],
                      ),
                      _divider(),
                      DropdownButtonFormField<EventRepeatFrequency?>(
                        value: _repeatFrequency,
                        decoration: const InputDecoration(
                          labelText: '반복',
                          prefixIcon: Icon(Icons.repeat, color: accent),
                        ),
                        items: const [
                          DropdownMenuItem<EventRepeatFrequency?>(
                            value: null,
                            child: Text('반복 안 함'),
                          ),
                          DropdownMenuItem(
                            value: EventRepeatFrequency.daily,
                            child: Text('매일'),
                          ),
                          DropdownMenuItem(
                            value: EventRepeatFrequency.weekly,
                            child: Text('매주'),
                          ),
                        ],
                        onChanged: (value) => setState(() {
                          _repeatFrequency = value;
                          if (_repeatUntil != null &&
                              _repeatUntil!.isBefore(_endDate)) {
                            _repeatUntil = null;
                          }
                        }),
                      ),
                      if (_repeatFrequency != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.event_repeat,
                            color: accent,
                          ),
                          title: Text(
                            _repeatUntil == null
                                ? '종료일 없음'
                                : '마지막 반복: ' + _dateLabel(_repeatUntil!),
                          ),
                          trailing: TextButton(
                            onPressed: _pickRepeatUntil,
                            child: Text(_repeatUntil == null ? '종료일 설정' : '변경'),
                          ),
                        ),
                      _divider(),
                      TextField(
                        controller: _memoController,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          icon: Icon(Icons.notes_outlined, color: accent),
                          hintText: '메모',
                          border: InputBorder.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  onPressed: _save,
                  child: Text(widget.initialEvent == null ? '저장' : '수정 완료'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _generalSchedule = '__general_schedule__';

class _TopTab extends StatelessWidget {
  const _TopTab({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.all(3),
    padding: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFF465ACB) : Colors.transparent,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: selected ? Colors.white : const Color(0xFF5063C6),
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
