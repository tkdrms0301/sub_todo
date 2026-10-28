import 'package:flutter/material.dart';

import '../models/calendar_event.dart';
import '../models/game.dart';
import '../models/quest.dart';

class GameSearchScreen extends StatefulWidget {
  const GameSearchScreen({
    required this.games,
    required this.events,
    required this.onEditQuest,
    required this.onDeleteQuest,
    required this.onEditEvent,
    required this.onDeleteEvent,
    super.key,
  });

  final List<GameInfo> games;
  final List<CalendarEvent> events;
  final Future<void> Function(GameInfo game, GameQuest quest) onEditQuest;
  final Future<void> Function(GameInfo game, GameQuest quest, DateTime date)
  onDeleteQuest;
  final Future<void> Function(CalendarEvent event) onEditEvent;
  final Future<void> Function(CalendarEvent event) onDeleteEvent;

  @override
  State<GameSearchScreen> createState() => _GameSearchScreenState();
}

class _GameSearchScreenState extends State<GameSearchScreen> {
  final _searchController = TextEditingController();
  String? _selectedGameId;

  String get _query => _searchController.text.trim().toLowerCase();

  List<GameInfo> get _filteredGames {
    if (_query.isEmpty) return widget.games;
    return widget.games.where((game) {
      if (game.name.toLowerCase().contains(_query)) return true;
      if (game.quests.any(
        (quest) => quest.title.toLowerCase().contains(_query),
      )) {
        return true;
      }
      return widget.events.any(
        (event) =>
            event.gameName == game.name &&
            (event.title.toLowerCase().contains(_query) ||
                (event.memo?.toLowerCase().contains(_query) ?? false)),
      );
    }).toList();
  }

  bool _matches(String value, GameInfo game) =>
      _query.isEmpty ||
      game.name.toLowerCase().contains(_query) ||
      value.toLowerCase().contains(_query);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _dateLabel(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${date.year}년 ${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
  }

  String _rangeLabel(DateTime start, DateTime end) {
    String compact(DateTime date) => '${date.month}.${date.day}';
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return compact(start);
    }
    return '${compact(start)}–${compact(end)}';
  }

  _AgendaDate _agendaForDate(GameInfo game, DateTime date) {
    final dailyEnabled = game.enabledTypes.contains(GameContentType.daily);
    final weeklyEnabled = game.enabledTypes.contains(GameContentType.weekly);
    final quests =
        game.quests.where((quest) {
          final enabled = quest.period == QuestPeriod.daily
              ? dailyEnabled
              : weeklyEnabled;
          return enabled &&
              quest.isApplicableOn(date) &&
              _matches(quest.title, game);
        }).toList()..sort((a, b) {
          if (a.period == b.period) return 0;
          return a.period == QuestPeriod.weekly ? -1 : 1;
        });
    final events = widget.events
        .where(
          (event) =>
              event.gameName == game.name &&
              event.includes(date) &&
              (_matches(event.title, game) ||
                  (event.memo != null && _matches(event.memo!, game))),
        )
        .toList();
    return _AgendaDate(date, quests, events);
  }

  Widget _actionButtons({
    required String itemLabel,
    required Future<void> Function() onEdit,
    required Future<void> Function() onDelete,
    bool isCompleted = false,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: '$itemLabel 수정',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: () async {
          await onEdit();
          if (mounted) setState(() {});
        },
        icon: Icon(
          Icons.edit_outlined,
          size: 20,
          color: isCompleted ? Colors.grey.shade400 : null,
        ),
      ),
      IconButton(
        tooltip: '$itemLabel 삭제',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        onPressed: () async {
          await onDelete();
          if (mounted) setState(() {});
        },
        icon: Icon(
          Icons.delete_outline,
          size: 20,
          color: isCompleted ? Colors.grey.shade400 : null,
        ),
      ),
    ],
  );

  Widget _questTile(GameInfo game, GameQuest quest, DateTime date) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: ListTile(
      dense: true,
      leading: Icon(
        quest.period == QuestPeriod.daily
            ? Icons.sports_esports
            : Icons.emoji_events,
        color: quest.period == QuestPeriod.daily
            ? game.color
            : Colors.amber.shade800,
      ),
      title: Text(
        quest.title,
        style: TextStyle(
          color: quest.isDoneOn(date) ? Colors.grey.shade500 : null,
        ),
      ),
      subtitle: Text(
        quest.period == QuestPeriod.daily
            ? '일일 퀘스트'
            : '주간 퀘스트 · ${quest.startDate == null || quest.endDate == null ? '반복' : _rangeLabel(quest.startDate!, quest.endDate!)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: quest.isDoneOn(date),
            activeColor: game.color,
            onChanged: (done) =>
                setState(() => quest.setDoneOn(date, done ?? false)),
          ),
          _actionButtons(
            itemLabel: '퀘스트',
            isCompleted: quest.isDoneOn(date),
            onEdit: () => widget.onEditQuest(game, quest),
            onDelete: () => widget.onDeleteQuest(game, quest, date),
          ),
        ],
      ),
    ),
  );

  Widget _eventTile(CalendarEvent event) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    child: ListTile(
      dense: true,
      leading: const Icon(Icons.event_note, color: Color(0xFFFFA726)),
      title: Text(event.title),
      subtitle: Text(
        [
          if (event.startTime != null)
            '${event.startTime}${event.endTime == null ? '' : '–${event.endTime}'}',
          if (event.repeatFrequency != null)
            event.repeatFrequency == EventRepeatFrequency.daily
                ? '매일 반복'
                : '매주 반복',
          if (event.memo != null) event.memo!,
        ].join(' · '),
      ),
      trailing: _actionButtons(
        itemLabel: '일정',
        onEdit: () => widget.onEditEvent(event),
        onDelete: () => widget.onDeleteEvent(event),
      ),
    ),
  );

  Widget _agendaDateTile(GameInfo game, DateTime date) {
    final item = _agendaForDate(game, date);
    if (item.quests.isEmpty && item.events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: Text(
          '${_dateLabel(date)}  ·  일정 없음',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: game.color.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dateLabel(item.date),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${item.quests.length + item.events.length}개',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
              ],
            ),
          ),
          ...item.events.map(_eventTile),
          ...item.quests.map((quest) => _questTile(game, quest, item.date)),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  Widget _agenda(GameInfo game) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final hasConfiguredItems =
        game.quests.any(
          (quest) =>
              (quest.period == QuestPeriod.daily &&
                  game.enabledTypes.contains(GameContentType.daily)) ||
              (quest.period == QuestPeriod.weekly &&
                  game.enabledTypes.contains(GameContentType.weekly)),
        ) ||
        widget.events.any((event) => event.gameName == game.name);
    if (!hasConfiguredItems) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            '등록된 퀘스트나 일정이 없습니다.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    final centerKey = const ValueKey<String>('today-agenda-center');
    return CustomScrollView(
      anchor: 0.5,
      center: centerKey,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _agendaDateTile(
                game,
                start.subtract(Duration(days: index + 1)),
              ),
            ),
          ),
        ),
        SliverPadding(
          key: centerKey,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  _agendaDateTile(game, start.add(Duration(days: index))),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final games = _filteredGames;
    final selected = widget.games
        .where((game) => game.id == _selectedGameId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(selected?.name ?? '게임별 일정 검색')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '게임·퀘스트·일정 검색',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: '검색어 지우기',
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 58,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: games
                  .map(
                    (game) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(game.name),
                        selected: _selectedGameId == game.id,
                        onSelected: (_) => setState(() {
                          _selectedGameId = game.id;
                        }),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Expanded(
            child: selected == null
                ? Center(
                    child: Text(
                      games.isEmpty
                          ? '검색 결과가 없습니다.'
                          : '게임을 선택하면 오늘을 기준으로 날짜별 일정을 볼 수 있습니다.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : Column(children: [Expanded(child: _agenda(selected))]),
          ),
        ],
      ),
    );
  }
}

class _AgendaDate {
  const _AgendaDate(this.date, this.quests, this.events);

  final DateTime date;
  final List<GameQuest> quests;
  final List<CalendarEvent> events;
}
