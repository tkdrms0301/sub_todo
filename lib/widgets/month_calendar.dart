import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../models/game.dart';
import '../models/quest.dart';

bool _enabled(GameInfo game, GameQuest quest) => game.enabledTypes.contains(
  quest.period == QuestPeriod.daily
      ? GameContentType.daily
      : GameContentType.weekly,
);

class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    required this.month,
    required this.selectedDate,
    required this.games,
    required this.events,
    required this.onSelect,
    this.expanded = false,
    this.weekOnly = false,
    super.key,
  });

  final DateTime month;
  final DateTime selectedDate;
  final List<GameInfo> games;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onSelect;
  final bool expanded;
  final bool weekOnly;

  static const _weekdays = ['일', '월', '화', '수', '목', '금', '토'];
  static const _dailyColor = Color(0xFF536DFE);
  static const _weeklyColor = Color(0xFF8E5CC7);
  static const _eventColor = Color(0xFFFFA726);
  static const _completedColor = Color(0xFF43A047);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _dateAt(DateTime weekStart, int column) =>
      weekStart.add(Duration(days: column));

  _CategoryCounts _countsForDate(DateTime date) {
    var daily = 0;
    var weekly = 0;
    for (final game in games) {
      for (final quest in game.quests) {
        if (!_enabled(game, quest) || !quest.isApplicableOn(date)) continue;
        if (quest.period == QuestPeriod.daily) {
          daily++;
        } else {
          weekly++;
        }
      }
    }
    return _CategoryCounts(
      daily: daily,
      weekly: weekly,
      schedules: events.where((event) => event.includes(date)).length,
    );
  }

  bool _questsDoneBetween(QuestPeriod period, DateTime start, DateTime end) {
    var foundQuest = false;
    for (
      var date = start;
      !date.isAfter(end);
      date = date.add(const Duration(days: 1))
    ) {
      for (final game in games) {
        for (final quest in game.quests) {
          if (quest.period != period ||
              !_enabled(game, quest) ||
              !quest.isApplicableOn(date)) {
            continue;
          }
          foundQuest = true;
          if (!quest.isDoneOn(date)) return false;
        }
      }
    }
    return foundQuest;
  }

  List<_CalendarBar> _expandedBarsForWeek(DateTime weekStart) {
    final bars = <_CalendarBar>[];
    final eventBars = <_CalendarBar>[];

    for (final event in events) {
      var column = 0;
      while (column < 7) {
        final date = _dateAt(weekStart, column);
        if (!event.includes(date)) {
          column++;
          continue;
        }
        final startColumn = column;
        while (column + 1 < 7 &&
            event.includes(_dateAt(weekStart, column + 1))) {
          column++;
        }
        final firstDay = _dateAt(weekStart, startColumn);
        final lastDay = _dateAt(weekStart, column);
        final occurrenceStart =
            event.occurrenceStartOn(firstDay) ?? event.startDate;
        final occurrenceEnd = event.occurrenceEndOn(firstDay) ?? event.endDate;
        eventBars.add(
          _CalendarBar(
            startColumn: startColumn,
            endColumn: column,
            label: event.title,
            color: _eventColor,
            kind: _CalendarBarKind.event,
            overflowKey: 'event:${identityHashCode(event)}:$startColumn',
            itemCount: 1,
            continuesLeft: occurrenceStart.isBefore(firstDay),
            continuesRight: occurrenceEnd.isAfter(lastDay),
          ),
        );
        column++;
      }
    }

    eventBars.sort((a, b) {
      final byStart = a.startColumn.compareTo(b.startColumn);
      return byStart != 0 ? byStart : b.endColumn.compareTo(a.endColumn);
    });
    final eventLanes = <List<_CalendarBar>>[];
    for (final bar in eventBars) {
      var laneIndex = eventLanes.indexWhere(
        (lane) => lane.every(
          (other) =>
              bar.endColumn < other.startColumn ||
              bar.startColumn > other.endColumn,
        ),
      );
      if (laneIndex < 0) {
        laneIndex = eventLanes.length;
        eventLanes.add([]);
      }
      eventLanes[laneIndex].add(
        _CalendarBar(
          startColumn: bar.startColumn,
          endColumn: bar.endColumn,
          label: bar.label,
          color: bar.color,
          priority: laneIndex,
          kind: _CalendarBarKind.event,
          overflowKey: bar.overflowKey,
          itemCount: bar.itemCount,
          continuesLeft: bar.continuesLeft,
          continuesRight: bar.continuesRight,
        ),
      );
    }
    bars.addAll(eventLanes.expand((lane) => lane));

    final weeklyGroups = <String, _WeeklyQuestGroup>{};
    for (var dayColumn = 0; dayColumn < 7; dayColumn++) {
      final date = _dateAt(weekStart, dayColumn);
      for (final game in games) {
        for (final quest in game.quests) {
          if (quest.period != QuestPeriod.weekly ||
              !_enabled(game, quest) ||
              !quest.isApplicableOn(date)) {
            continue;
          }
          final occurrenceStart = quest.occurrenceStartOn(date)!;
          final occurrenceEnd = quest.occurrenceEndOn(date)!;
          final key =
              '${occurrenceStart.toIso8601String()}|'
              '${occurrenceEnd.toIso8601String()}';
          final group = weeklyGroups.putIfAbsent(
            key,
            () => _WeeklyQuestGroup(
              startDate: occurrenceStart,
              endDate: occurrenceEnd,
              startColumn: dayColumn,
              endColumn: dayColumn,
            ),
          );
          group.startColumn = dayColumn < group.startColumn
              ? dayColumn
              : group.startColumn;
          group.endColumn = dayColumn > group.endColumn
              ? dayColumn
              : group.endColumn;
          if (!group.entries.any((entry) => identical(entry.quest, quest))) {
            group.entries.add(_QuestBarEntry(game.alias, quest));
          }
        }
      }
    }

    final sortedWeeklyGroups = weeklyGroups.values.toList()
      ..sort((a, b) {
        final byStart = a.startColumn.compareTo(b.startColumn);
        return byStart != 0 ? byStart : b.endColumn.compareTo(a.endColumn);
      });
    final weeklyLanes = <List<_WeeklyQuestGroup>>[];
    for (final group in sortedWeeklyGroups) {
      var laneIndex = weeklyLanes.indexWhere(
        (lane) => lane.every(
          (other) =>
              group.endColumn < other.startColumn ||
              group.startColumn > other.endColumn,
        ),
      );
      if (laneIndex < 0) {
        laneIndex = weeklyLanes.length;
        weeklyLanes.add([]);
      }
      group.lane = laneIndex;
      weeklyLanes[laneIndex].add(group);
    }
    final weeklyLane = eventLanes.length;
    for (final group in sortedWeeklyGroups) {
      final overflowKey =
          'weekly:${group.startDate.toIso8601String()}|'
          '${group.endDate.toIso8601String()}';
      final startDay = _dateAt(weekStart, group.startColumn);
      final endDay = _dateAt(weekStart, group.endColumn);
      final completedCount = group.entries
          .where((entry) => entry.quest.isDoneOn(group.startDate))
          .length;
      final isComplete = completedCount == group.entries.length;
      final aliasCompletion = <String, bool>{};
      for (final entry in group.entries) {
        final done = entry.quest.isDoneOn(group.startDate);
        aliasCompletion.update(
          entry.alias,
          (allDone) => allDone && done,
          ifAbsent: () => done,
        );
      }
      bars.add(
        _CalendarBar(
          startColumn: group.startColumn,
          endColumn: group.endColumn,
          label: '주간 $completedCount/${group.entries.length}',
          color: isComplete ? _completedColor : _weeklyColor,
          isComplete: isComplete,
          priority: weeklyLane + group.lane * 2,
          kind: _CalendarBarKind.range,
          overflowKey: overflowKey,
          itemCount: group.entries.length,
          continuesLeft: group.startDate.isBefore(startDay),
          continuesRight: group.endDate.isAfter(endDay),
        ),
      );
      bars.add(
        _CalendarBar(
          startColumn: group.startColumn,
          endColumn: group.endColumn,
          label: '| ',
          color: _weeklyColor,
          priority: weeklyLane + group.lane * 2 + 1,
          kind: _CalendarBarKind.detail,
          overflowKey: overflowKey,
          itemCount: group.entries.length,
          details: aliasCompletion.entries
              .map(
                (entry) => _CalendarBarDetail(
                  entry.key,
                  isDone: entry.value,
                  fadeWhenDone: true,
                ),
              )
              .toList(),
          continuesLeft: false,
          continuesRight: false,
        ),
      );
    }

    final dailyLane = weeklyLane + weeklyLanes.length * 2;
    for (var dayColumn = 0; dayColumn < 7; dayColumn++) {
      final date = _dateAt(weekStart, dayColumn);
      final dailyQuests = <_QuestBarEntry>[];
      for (final game in games) {
        for (final quest in game.quests) {
          if (quest.period == QuestPeriod.daily &&
              _enabled(game, quest) &&
              quest.isApplicableOn(date)) {
            dailyQuests.add(_QuestBarEntry(game.alias, quest));
          }
        }
      }
      if (dailyQuests.isEmpty) continue;
      final completedCount = dailyQuests
          .where((entry) => entry.quest.isDoneOn(date))
          .length;
      final isComplete = completedCount == dailyQuests.length;
      final overflowKey = 'daily:${date.year}-${date.month}-${date.day}';
      bars.add(
        _CalendarBar(
          startColumn: dayColumn,
          endColumn: dayColumn,
          label: '일일 $completedCount/${dailyQuests.length}',
          color: isComplete ? _completedColor : _dailyColor,
          isComplete: isComplete,
          priority: dailyLane,
          kind: _CalendarBarKind.range,
          overflowKey: overflowKey,
          itemCount: dailyQuests.length,
          continuesLeft: false,
          continuesRight: false,
        ),
      );
    }

    return bars;
  }

  List<_CalendarBar> _barsForWeek(DateTime weekStart) {
    if (expanded && !weekOnly) return _expandedBarsForWeek(weekStart);
    final bars = <_CalendarBar>[];

    final counts = List.generate(
      7,
      (column) => _countsForDate(_dateAt(weekStart, column)),
    );
    final categories = [
      (
        label: '일정',
        color: _eventColor,
        mergeAdjacent: true,
        count: (int i) => counts[i].schedules,
      ),
      (
        label: '주간',
        color: _weeklyColor,
        mergeAdjacent: true,
        count: (int i) => counts[i].weekly,
      ),
      (
        label: '일일',
        color: _dailyColor,
        mergeAdjacent: false,
        count: (int i) => counts[i].daily,
      ),
    ];
    int categoryCount(_CategoryCounts value, int index) => switch (index) {
      0 => value.schedules,
      1 => value.weekly,
      _ => value.daily,
    };
    final previousDayCounts = _countsForDate(
      weekStart.subtract(const Duration(days: 1)),
    );
    final nextDayCounts = _countsForDate(_dateAt(weekStart, 7));

    // Join adjacent schedule and weekly quest days; daily quests stay per-day.
    for (
      var categoryIndex = 0;
      categoryIndex < categories.length;
      categoryIndex++
    ) {
      final category = categories[categoryIndex];

      int laneFor(int dayColumn) {
        if (categoryIndex == 0) return 0;
        var lane = 0;
        for (final existing in bars) {
          if (dayColumn >= existing.startColumn &&
              dayColumn <= existing.endColumn &&
              existing.priority >= lane) {
            lane = existing.priority + 1;
          }
        }
        return lane;
      }

      var column = 0;
      while (column < 7) {
        final count = category.count(column);
        if (count == 0) {
          column++;
          continue;
        }
        final startColumn = column;
        while (category.mergeAdjacent &&
            column + 1 < 7 &&
            category.count(column + 1) > 0) {
          column++;
        }
        final endColumn = column;
        var lane = 0;
        for (var day = startColumn; day <= endColumn; day++) {
          final dayLane = laneFor(day);
          if (dayLane > lane) lane = dayLane;
        }
        final isComplete =
            categoryIndex > 0 &&
            _questsDoneBetween(
              categoryIndex == 1 ? QuestPeriod.weekly : QuestPeriod.daily,
              _dateAt(weekStart, startColumn),
              _dateAt(weekStart, endColumn),
            );
        bars.add(
          _CalendarBar(
            startColumn: startColumn,
            endColumn: endColumn,
            label: '${category.label} $count',
            color: isComplete ? _completedColor : category.color,
            priority: lane,
            isComplete: isComplete,
            continuesLeft:
                category.mergeAdjacent &&
                startColumn == 0 &&
                categoryCount(previousDayCounts, categoryIndex) > 0,
            continuesRight:
                category.mergeAdjacent &&
                endColumn == 6 &&
                categoryCount(nextDayCounts, categoryIndex) > 0,
          ),
        );
        column++;
      }
    }

    bars.sort((a, b) {
      final byStart = a.startColumn.compareTo(b.startColumn);
      if (byStart != 0) return byStart;
      return b.endColumn.compareTo(a.endColumn);
    });
    return bars;
  }

  List<List<_CalendarBar>> _assignLanes(List<_CalendarBar> bars) {
    if (bars.isEmpty) return [];
    final laneCount = bars.fold<int>(
      0,
      (count, bar) => bar.priority >= count ? bar.priority + 1 : count,
    );
    final lanes = List.generate(laneCount, (_) => <_CalendarBar>[]);
    for (final bar in bars) {
      lanes[bar.priority].add(bar);
    }
    for (final lane in lanes) {
      lane.sort((a, b) => a.startColumn.compareTo(b.startColumn));
    }
    return lanes.where((lane) => lane.isNotEmpty).toList();
  }

  List<List<_CalendarBar>> _visibleLanesForWeek(
    List<_CalendarBar> bars, {
    required bool compactBars,
    required bool expandedMonth,
  }) {
    final lanes = _assignLanes(bars);
    if (expandedMonth && lanes.length > 4) {
      const visibleContentLaneCount = 3;
      final overflowByDate = <int, Map<String, int>>{};
      for (var dayColumn = 0; dayColumn < 7; dayColumn++) {
        final hiddenItems = <String, int>{};
        for (final lane in lanes.skip(visibleContentLaneCount)) {
          for (final bar in lane) {
            final key = bar.overflowKey;
            if (key == null ||
                bar.itemCount <= 0 ||
                dayColumn < bar.startColumn ||
                dayColumn > bar.endColumn) {
              continue;
            }
            hiddenItems.update(
              key,
              (previous) => previous > bar.itemCount ? previous : bar.itemCount,
              ifAbsent: () => bar.itemCount,
            );
          }
        }
        if (hiddenItems.isNotEmpty) overflowByDate[dayColumn] = hiddenItems;
      }
      final overflowBars = <_CalendarBar>[];
      for (final entry in overflowByDate.entries) {
        final count = entry.value.values.fold<int>(
          0,
          (sum, itemCount) => sum + itemCount,
        );
        overflowBars.add(
          _CalendarBar(
            startColumn: entry.key,
            endColumn: entry.key,
            label: '외 ${count}개',
            color: Colors.blueGrey,
            priority: visibleContentLaneCount,
            kind: _CalendarBarKind.summary,
            continuesLeft: false,
            continuesRight: false,
          ),
        );
      }
      return [...lanes.take(visibleContentLaneCount), overflowBars];
    }
    if (compactBars && lanes.length > 5) {
      return [
        ...lanes.take(4),
        [
          _CalendarBar(
            startColumn: 0,
            endColumn: 6,
            label: '외 ${lanes.length - 4}개 더',
            color: Colors.blueGrey,
            priority: 0,
            continuesLeft: false,
            continuesRight: false,
          ),
        ],
      ];
    }
    return lanes;
  }

  Widget _buildBarLane(List<_CalendarBar> bars) {
    final compactBars = !expanded || weekOnly;
    final textBars = expanded && !weekOnly;
    final bar = bars.first;
    final laneHeight = compactBars ? 8.0 : _barLaneHeight(bars);
    final children = <Widget>[];
    var nextColumn = 0;
    for (final bar in bars) {
      if (bar.startColumn > nextColumn) {
        children.add(
          Expanded(flex: bar.startColumn - nextColumn, child: const SizedBox()),
        );
      }
      children.add(
        Expanded(
          flex: bar.endColumn - bar.startColumn + 1,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compactBars || textBars ? 4 : 0,
              vertical: 1,
            ),
            child: Container(
              height: laneHeight - 2,
              alignment:
                  bar.kind == _CalendarBarKind.event ||
                      bar.kind == _CalendarBarKind.summary
                  ? Alignment.center
                  : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: compactBars
                    ? bar.color.withValues(alpha: 0.68)
                    : textBars
                    ? (bar.kind == _CalendarBarKind.event
                          ? bar.color.withValues(alpha: 0.18)
                          : bar.kind == _CalendarBarKind.range
                          ? bar.color.withValues(
                              alpha: bar.isComplete ? 0.52 : 0.18,
                            )
                          : null)
                    : bar.color.withValues(alpha: 0.24),
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(!bar.continuesLeft ? 5 : 2),
                  right: Radius.circular(!bar.continuesRight ? 5 : 2),
                ),
              ),
              child: compactBars
                  ? const SizedBox.shrink()
                  : textBars
                  ? Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: bar.kind == _CalendarBarKind.detail ? 2 : 3,
                      ),
                      child: _calendarBarText(bar),
                    )
                  : Text(
                      bar.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      style: TextStyle(
                        color: bar.color.computeLuminance() < 0.25
                            ? bar.color
                            : Color.lerp(bar.color, Colors.black, 0.25),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      );
      nextColumn = bar.endColumn + 1;
    }
    if (nextColumn < 7) {
      children.add(Expanded(flex: 7 - nextColumn, child: const SizedBox()));
    }
    return Row(children: children);
  }

  double _barLaneHeight(List<_CalendarBar> bars) {
    final bar = bars.first;
    return switch (bar.kind) {
      _CalendarBarKind.event || _CalendarBarKind.range => 19.0,
      _CalendarBarKind.summary || _CalendarBarKind.detail => 17.0,
      _CalendarBarKind.marker => 15.0,
    };
  }

  Widget _calendarBarText(_CalendarBar bar) {
    final textStyle = TextStyle(
      color: bar.kind == _CalendarBarKind.detail
          ? Color.lerp(bar.color, Colors.black, 0.3)
          : bar.color.computeLuminance() < 0.25
          ? bar.color
          : Color.lerp(bar.color, Colors.black, 0.3),
      fontSize: bar.kind == _CalendarBarKind.detail ? 7 : 8,
      fontWeight: FontWeight.w700,
    );
    if (bar.kind != _CalendarBarKind.detail || bar.details.isEmpty) {
      return Text(
        bar.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        textAlign:
            bar.kind == _CalendarBarKind.event ||
                bar.kind == _CalendarBarKind.summary
            ? TextAlign.center
            : TextAlign.left,
        style: textStyle,
      );
    }

    final spans = <TextSpan>[];
    for (var index = 0; index < bar.details.length; index++) {
      final entry = bar.details[index];
      if (index == 0) {
        spans.add(const TextSpan(text: '| '));
      } else {
        spans.add(const TextSpan(text: ' · '));
      }
      spans.add(
        TextSpan(
          text: entry.text,
          style: TextStyle(
            color: entry.isDone && entry.fadeWhenDone
                ? textStyle.color?.withValues(alpha: 0.55)
                : null,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: textStyle,
    );
  }

  Widget _buildWeek(
    BuildContext context,
    DateTime weekStart,
    ColorScheme scheme,
    double expandedDateHeight,
    double extraBottomSpacing,
  ) {
    final weekBars = _barsForWeek(weekStart);
    final compactBars = !expanded || weekOnly;
    final expandedMonth = expanded && !weekOnly;
    final visibleLanes = _visibleLanesForWeek(
      weekBars,
      compactBars: compactBars,
      expandedMonth: expandedMonth,
    );
    final selectedColumn = _dateOnly(selectedDate)
        .difference(_dateOnly(weekStart))
        .inDays;
    return Padding(
      padding: EdgeInsets.only(
        bottom: expandedMonth ? 0 : (expanded ? 5 : 1) + extraBottomSpacing,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / 7;
          return SizedBox(
            width: constraints.maxWidth,
            child: Stack(
              children: [
                Column(
                  children: [
                    Row(
                      children: List.generate(7, (column) {
                        final date = _dateAt(weekStart, column);
                        final inMonth = date.month == month.month;
                        final today = _sameDay(date, DateTime.now());
                        return Expanded(
                          child: SizedBox(
                            height: expandedDateHeight,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                Container(
                                  width: 27,
                                  height: 27,
                                  alignment: Alignment.center,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      if (today)
                                        Container(
                                          width: 19,
                                          height: 19,
                                          decoration: BoxDecoration(
                                            color: scheme.primary,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        date.day.toString(),
                                        style: TextStyle(
                                          color: today
                                              ? Colors.white
                                              : !inMonth
                                              ? Colors.grey.shade400
                                              : date.weekday == DateTime.sunday
                                              ? Colors.red.shade400
                                              : date.weekday ==
                                                    DateTime.saturday
                                              ? Colors.blue.shade600
                                              : Colors.black87,
                                          fontWeight: today
                                              ? FontWeight.w800
                                              : null,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox.shrink(),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                    ...visibleLanes.map(_buildBarLane),
                    if (compactBars) const SizedBox(height: 13),
                    if (expandedMonth) SizedBox(height: 5 + extraBottomSpacing),
                  ],
                ),
                Positioned.fill(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: List.generate(
                      7,
                      (column) => Expanded(
                        child: Padding(
                          padding: expandedMonth
                              ? EdgeInsets.zero
                              : const EdgeInsets.fromLTRB(2, 1, 2, 1),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => onSelect(_dateAt(weekStart, column)),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (selectedColumn >= 0 && selectedColumn < 7)
                  Positioned(
                    left: selectedColumn * cellWidth + (expandedMonth ? 0 : 2),
                    top: expandedMonth ? 0 : 1,
                    bottom: expandedMonth ? 0 : 1,
                    width: cellWidth - (expandedMonth ? 0 : 4),
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.primary, width: 1.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final leadingDays = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: leadingDays));
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final weekStarts = weekOnly
                ? [
                    _dateOnly(selectedDate)
                        .subtract(Duration(days: selectedDate.weekday % 7)),
                  ]
                : List.generate(
                    6,
                    (week) => gridStart.add(Duration(days: week * 7)),
                  );
            final compactBars = !expanded || weekOnly;
            final barHeight = weekStarts.fold<double>(0, (total, start) {
              final lanes = _visibleLanesForWeek(
                _barsForWeek(start),
                compactBars: compactBars,
                expandedMonth: expanded && !weekOnly,
              );
              return total +
                  lanes.fold<double>(
                    0,
                    (weekHeight, lane) =>
                        weekHeight + (compactBars ? 14 : _barLaneHeight(lane)),
                  );
            });
            // In the full-month view, distribute the remaining height across
            // week rows so the calendar fills the available screen area.
            final dateHeight = expanded ? 27.0 : 45.0;
            final extraWeekSpacing = expanded && !weekOnly
                ? ((constraints.maxHeight -
                              30 -
                              dateHeight * weekStarts.length -
                              barHeight -
                              weekStarts.length * 5) /
                          weekStarts.length)
                      .clamp(0.0, constraints.maxHeight)
                      .toDouble()
                : 0.0;
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Row(
                  children: _weekdays
                      .map(
                        (day) => Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: TextStyle(
                                color: day == '일'
                                    ? Colors.red.shade400
                                    : Colors.grey,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 8),
                ...weekStarts.map(
                  (weekStart) => _buildWeek(
                    context,
                    weekStart,
                    scheme,
                    expanded ? dateHeight : 27,
                    extraWeekSpacing,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class _CategoryCounts {
  const _CategoryCounts({
    required this.daily,
    required this.weekly,
    required this.schedules,
  });

  final int daily;
  final int weekly;
  final int schedules;
}

class _QuestBarEntry {
  const _QuestBarEntry(this.alias, this.quest);

  final String alias;
  final GameQuest quest;
}

class _CalendarBarDetail {
  const _CalendarBarDetail(
    this.text, {
    this.isDone = false,
    this.fadeWhenDone = false,
  });

  final String text;
  final bool isDone;
  final bool fadeWhenDone;
}

class _WeeklyQuestGroup {
  _WeeklyQuestGroup({
    required this.startDate,
    required this.endDate,
    required this.startColumn,
    required this.endColumn,
  });

  final DateTime startDate;
  final DateTime endDate;
  int startColumn;
  int endColumn;
  int lane = 0;
  final List<_QuestBarEntry> entries = [];
}

class _CalendarBar {
  const _CalendarBar({
    required this.startColumn,
    required this.endColumn,
    required this.label,
    required this.color,
    this.priority = 0,
    this.kind = _CalendarBarKind.marker,
    this.isComplete = false,
    this.details = const [],
    this.overflowKey,
    this.itemCount = 0,
    required this.continuesLeft,
    required this.continuesRight,
  });

  final int startColumn;
  final int endColumn;
  final String label;
  final Color color;
  final int priority;
  final _CalendarBarKind kind;
  final bool isComplete;
  final List<_CalendarBarDetail> details;
  final String? overflowKey;
  final int itemCount;
  final bool continuesLeft;
  final bool continuesRight;
}

enum _CalendarBarKind { marker, event, range, detail, summary }
