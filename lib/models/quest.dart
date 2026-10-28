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
  }) : startDate = startDate == null ? null : _dateOnly(startDate),
       endDate = endDate == null ? null : _dateOnly(endDate);

  String title;
  QuestPeriod period;

  /// The first selected weekly window. It repeats every seven days.
  DateTime? startDate;
  DateTime? endDate;
  final Set<String> _completedKeys = {};
  final Set<String> _excludedDailyDates = {};

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
