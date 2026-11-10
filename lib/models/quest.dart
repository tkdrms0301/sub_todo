enum QuestPeriod { daily, weekly }

extension QuestPeriodLabel on QuestPeriod {
  String get label => this == QuestPeriod.daily ? '일일' : '주간';
}

class GameQuest {
  GameQuest({
    required this.title,
    required this.period,
    DateTime? startDate,
    DateTime? endDate,
    Iterable<String> completedDates = const [],
    Iterable<String> excludedDailyDates = const [],
  }) : startDate = startDate == null ? null : _dateOnly(startDate),
       endDate = endDate == null ? null : _dateOnly(endDate),
       _completedKeys = {...completedDates},
       _excludedDailyDates = {...excludedDailyDates};

  String title;
  QuestPeriod period;

  /// The first selected weekly window. It repeats every seven days.
  DateTime? startDate;
  DateTime? endDate;
  final Set<String> _completedKeys;
  final Set<String> _excludedDailyDates;

  Map<String, dynamic> toJson() => {
    'title': title,
    'period': period.name,
    if (startDate != null) 'startDate': _dateString(startDate!),
    if (endDate != null) 'endDate': _dateString(endDate!),
    'completedDates': _completedKeys.toList()..sort(),
    'excludedDailyDates': _excludedDailyDates.toList()..sort(),
  };

  factory GameQuest.fromJson(Map<String, dynamic> json) {
    final title = json['title'];
    final periodName = json['period'];
    if (title is! String || title.trim().isEmpty || periodName is! String) {
      throw const FormatException('퀘스트의 제목 또는 유형이 올바르지 않습니다.');
    }
    final periodMatches = QuestPeriod.values
        .where((value) => value.name == periodName)
        .toList();
    if (periodMatches.isEmpty) {
      throw FormatException('알 수 없는 퀘스트 유형: $periodName');
    }
    DateTime? parseDate(Object? value, String field) {
      if (value == null) return null;
      if (value is! String) {
        throw FormatException('$field는 YYYY-MM-DD 문자열이어야 합니다.');
      }
      final parsed = DateTime.tryParse(value);
      if (parsed == null) throw FormatException('$field 날짜가 올바르지 않습니다.');
      return _dateOnly(parsed);
    }

    List<String> parseDateKeys(Object? value, String field) {
      if (value == null) return const [];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('$field는 날짜 문자열 배열이어야 합니다.');
      }
      return value.cast<String>();
    }

    return GameQuest(
      title: title.trim(),
      period: periodMatches.first,
      startDate: parseDate(json['startDate'], 'startDate'),
      endDate: parseDate(json['endDate'], 'endDate'),
      completedDates: parseDateKeys(json['completedDates'], 'completedDates'),
      excludedDailyDates: parseDateKeys(
        json['excludedDailyDates'],
        'excludedDailyDates',
      ),
    );
  }

  void update({
    required String title,
    required QuestPeriod period,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    final nextStart = startDate == null ? null : _dateOnly(startDate);
    final nextEnd = endDate == null ? null : _dateOnly(endDate);
    if (this.period != period ||
        this.startDate != nextStart ||
        this.endDate != nextEnd) {
      _completedKeys.clear();
      _excludedDailyDates.clear();
    }
    this.title = title;
    this.period = period;
    this.startDate = nextStart;
    this.endDate = nextEnd;
  }

  DateTime? occurrenceStartOn(DateTime date) {
    if (period == QuestPeriod.daily || startDate == null || endDate == null) {
      return null;
    }
    final day = _dateOnly(date);
    if (day.isBefore(startDate!)) return null;
    final cycle = day.difference(startDate!).inDays ~/ 7;
    final start = startDate!.add(Duration(days: cycle * 7));
    final end = endDate!.add(Duration(days: cycle * 7));
    return day.isAfter(end) ? null : start;
  }

  DateTime? occurrenceEndOn(DateTime date) {
    final start = occurrenceStartOn(date);
    if (start == null) return null;
    return endDate!.add(Duration(days: start.difference(startDate!).inDays));
  }

  bool isApplicableOn(DateTime date) => period == QuestPeriod.daily
      ? !_excludedDailyDates.contains(_dateKey(date))
      : occurrenceStartOn(date) != null;

  void excludeDailyDate(DateTime date) {
    if (period != QuestPeriod.daily) return;
    final key = _dateKey(date);
    _excludedDailyDates.add(key);
    _completedKeys.remove(key);
  }

  bool isDoneOn(DateTime date) =>
      isApplicableOn(date) && _completedKeys.contains(_key(date));

  void setDoneOn(DateTime date, bool done) {
    if (!isApplicableOn(date)) return;
    final key = _key(date);
    if (done) {
      _completedKeys.add(key);
    } else {
      _completedKeys.remove(key);
    }
  }

  String _key(DateTime date) {
    final day = _dateOnly(date);
    final normalized = period == QuestPeriod.daily
        ? day
        : occurrenceStartOn(day) ??
              day.subtract(Duration(days: day.weekday - DateTime.monday));
    final year = normalized.year.toString().padLeft(4, '0');
    final month = normalized.month.toString().padLeft(2, '0');
    final number = normalized.day.toString().padLeft(2, '0');
    return '$year-$month-$number';
  }

  String _dateKey(DateTime date) {
    final day = _dateOnly(date);
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final number = day.day.toString().padLeft(2, '0');
    return '$year-$month-$number';
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateString(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
