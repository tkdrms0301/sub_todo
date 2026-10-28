enum EventRepeatFrequency { daily, weekly }

extension EventRepeatLabel on EventRepeatFrequency {
  String get label => this == EventRepeatFrequency.daily ? '매일' : '매주';
}

class CalendarEvent {
  CalendarEvent({
    this.gameName,
    required this.title,
    required this.startDate,
    required this.endDate,
    this.startTime,
    this.endTime,
    this.memo,
    this.allDay = false,
    this.repeatFrequency,
    this.repeatUntil,
  });

  String? gameName;
  final String title;

  /// Dates of the first event occurrence. Repeated occurrences retain this duration.
  final DateTime startDate;
  final DateTime endDate;
  final String? startTime;
  final String? endTime;
  final String? memo;
  final bool allDay;
  final EventRepeatFrequency? repeatFrequency;

  /// Inclusive final occurrence start date; null means repeat without an end.
  final DateTime? repeatUntil;

  DateTime? occurrenceStartOn(DateTime date) {
    if (!includes(date)) return null;
    if (repeatFrequency == null) return startDate;
    final day = DateTime(date.year, date.month, date.day);
    final interval = repeatFrequency == EventRepeatFrequency.daily ? 1 : 7;
    final occurrence = day.difference(startDate).inDays ~/ interval;
    return startDate.add(Duration(days: occurrence * interval));
  }

  DateTime? occurrenceEndOn(DateTime date) {
    final start = occurrenceStartOn(date);
    return start?.add(Duration(days: endDate.difference(startDate).inDays));
  }

  bool includes(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (repeatFrequency == null) {
      return !day.isBefore(startDate) && !day.isAfter(endDate);
    }
    if (day.isBefore(startDate)) return false;
    final interval = repeatFrequency == EventRepeatFrequency.daily ? 1 : 7;
    final duration = endDate.difference(startDate).inDays;
    final daysSinceStart = day.difference(startDate).inDays;
    final occurrence = daysSinceStart ~/ interval;
    final occurrenceStart = startDate.add(
      Duration(days: occurrence * interval),
    );
    if (repeatUntil != null && occurrenceStart.isAfter(repeatUntil!))
      return false;
    final occurrenceEnd = occurrenceStart.add(Duration(days: duration));
    return !day.isBefore(occurrenceStart) && !day.isAfter(occurrenceEnd);
  }

  Map<String, dynamic> toJson() => {
    if (gameName != null && gameName!.isNotEmpty) 'game': gameName,
    'title': title,
    'startDate': _dateString(startDate),
    'endDate': _dateString(endDate),
    'allDay': allDay,
    if (startTime != null) 'startTime': startTime,
    if (endTime != null) 'endTime': endTime,
    if (memo != null && memo!.isNotEmpty) 'memo': memo,
    if (repeatFrequency != null)
      'repeat': {
        'frequency': repeatFrequency!.name,
        if (repeatUntil != null) 'until': _dateString(repeatUntil!),
      },
  };

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(Object? value, String field) {
      if (value is! String)
        throw FormatException('$field는 YYYY-MM-DD 문자열이어야 합니다.');
      final parsed = DateTime.tryParse(value);
      if (parsed == null) throw FormatException('$field 날짜가 올바르지 않습니다.');
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    String requiredText(String field) {
      final value = json[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$field 값이 비어 있습니다.');
      }
      return value.trim();
    }

    String? optionalTime(String field) {
      final value = json[field];
      if (value == null || value == '') return null;
      if (value is! String ||
          !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
        throw FormatException('$field 값은 HH:mm 형식이어야 합니다.');
      }
      return value;
    }

    final start = parseDate(json['startDate'], 'startDate');
    final end = parseDate(json['endDate'], 'endDate');
    if (end.isBefore(start)) {
      throw const FormatException('종료일은 시작일보다 빠를 수 없습니다.');
    }
    EventRepeatFrequency? frequency;
    DateTime? repeatUntil;
    final repeat = json['repeat'];
    if (repeat != null) {
      if (repeat is! Map) throw const FormatException('repeat는 객체여야 합니다.');
      final name = repeat['frequency'];
      for (final value in EventRepeatFrequency.values) {
        if (value.name == name) frequency = value;
      }
      if (frequency == null)
        throw const FormatException('repeat.frequency는 daily 또는 weekly여야 합니다.');
      if (repeat['until'] != null)
        repeatUntil = parseDate(repeat['until'], 'repeat.until');
    }
    final gameValue = json['game'];
    final memoValue = json['memo'];
    return CalendarEvent(
      gameName: gameValue is String && gameValue.trim().isNotEmpty
          ? gameValue.trim()
          : null,
      title: requiredText('title'),
      startDate: start,
      endDate: end,
      startTime: optionalTime('startTime'),
      endTime: optionalTime('endTime'),
      memo: memoValue is String && memoValue.trim().isNotEmpty
          ? memoValue.trim()
          : null,
      allDay:
          json['allDay'] == true ||
          (json['startTime'] == null && json['endTime'] == null),
      repeatFrequency: frequency,
      repeatUntil: repeatUntil,
    );
  }
}

String _dateString(DateTime value) =>
    value.year.toString().padLeft(4, '0') +
    '-' +
    value.month.toString().padLeft(2, '0') +
    '-' +
    value.day.toString().padLeft(2, '0');
