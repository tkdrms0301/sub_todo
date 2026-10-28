import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/calendar_event.dart';
import '../models/game.dart';
import '../models/quest.dart';
import '../widgets/month_calendar.dart';
import '../widgets/scheduled_events.dart';
import '../widgets/selected_day_quests.dart';
import 'event_entry_screen.dart';
import 'game_search_screen.dart';
import 'game_settings_dialog.dart';
import 'quest_entry_dialog.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

enum _CalendarMode { full, month, week }

class _CalendarScreenState extends State<CalendarScreen> {
  final List<GameInfo> _games = [];
  List<CalendarEvent> _events = [];
  String? _scheduleLoadError;
  String? _gamePresetLoadError;
  late DateTime _selectedDate = _dateOnly(DateTime.now());
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  _CalendarMode _calendarMode = _CalendarMode.month;
  int? _swipePointer;
  double? _swipeStartY;
  double? _swipeStartX;
  double _horizontalDragDistance = 0;
  int _monthSlideDirection = 1;

  bool get _calendarExpanded => _calendarMode == _CalendarMode.full;

  void _onPointerDown(PointerDownEvent event) {
    _swipePointer = event.pointer;
    _swipeStartY = event.position.dy;
    _swipeStartX = event.position.dx;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _swipePointer ||
        _swipeStartY == null ||
        _swipeStartX == null) {
      return;
    }
    final delta = event.position.dy - _swipeStartY!;
    final deltaX = event.position.dx - _swipeStartX!;
    _swipePointer = null;
    _swipeStartY = null;
    _swipeStartX = null;
    if (delta.abs() < 32 || delta.abs() <= deltaX.abs()) return;

    setState(() {
      if (delta < 0) {
        // Up: full month -> main month -> selected week and details.
        if (_calendarMode == _CalendarMode.full) {
          _calendarMode = _CalendarMode.month;
        } else if (_calendarMode == _CalendarMode.month) {
          _calendarMode = _CalendarMode.week;
        }
      } else {
        // Down: selected week and details -> main month -> full month.
        if (_calendarMode == _CalendarMode.week) {
          _calendarMode = _CalendarMode.month;
        } else if (_calendarMode == _CalendarMode.month) {
          _calendarMode = _CalendarMode.full;
        }
      }
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer == _swipePointer) {
      _swipePointer = null;
      _swipeStartY = null;
      _swipeStartX = null;
    }
  }

  Widget _calendarSwipeRegion(Widget child) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
    onHorizontalDragUpdate: (details) {
      _horizontalDragDistance += details.primaryDelta ?? 0;
    },
    onHorizontalDragEnd: (_) {
      if (_horizontalDragDistance.abs() < 40) return;
      _changeMonth(_horizontalDragDistance < 0 ? 1 : -1);
    },
    child: Listener(
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: child,
    ),
  );

  @override
  void initState() {
    super.initState();
    _loadScheduleFile();
    _loadGamePresets();
  }

  Future<void> _loadGamePresets() async {
    try {
      final raw = await rootBundle.loadString('assets/game_quests.json');
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> || decoded['games'] is! List) {
        throw const FormatException('JSON에 games 배열이 필요합니다.');
      }
      final presets = <GameInfo>[];
      final today = _dateOnly(DateTime.now());
      final monday = today.subtract(
        Duration(days: today.weekday - DateTime.monday),
      );

      for (final value in decoded['games'] as List) {
        if (value is! Map<String, dynamic>) {
          throw const FormatException('각 게임 설정은 JSON 객체여야 합니다.');
        }
        final name = value['name'];
        if (name is! String || name.trim().isEmpty) {
          throw const FormatException('게임 이름이 비어 있습니다.');
        }
        final rawTypes = value['types'];
        if (rawTypes is! List) {
          throw FormatException('$name 게임에 types 배열이 필요합니다.');
        }
        final types = <GameContentType>{};
        for (final typeName in rawTypes) {
          final matches = GameContentType.values
              .where((type) => type.name == typeName)
              .toList();
          if (matches.isEmpty) {
            throw FormatException('$name 게임의 알 수 없는 유형: $typeName');
          }
          types.add(matches.first);
        }
        final game = GameInfo(
          name: name.trim(),
          alias: value['alias'] is String ? value['alias'] as String : null,
          color: Colors.primaries[presets.length % Colors.primaries.length],
          enabledTypes: types,
        );
        final rawQuests = value['quests'] ?? const [];
        if (rawQuests is! List) {
          throw FormatException('$name 게임의 quests는 배열이어야 합니다.');
        }
        for (final questValue in rawQuests) {
          if (questValue is! Map<String, dynamic>) {
            throw FormatException('$name 게임의 각 퀘스트 설정은 객체여야 합니다.');
          }
          final periodMatches = QuestPeriod.values
              .where((period) => period.name == questValue['period'])
              .toList();
          final title = questValue['title'];
          if (periodMatches.isEmpty ||
              title is! String ||
              title.trim().isEmpty) {
            throw FormatException('$name 게임의 퀘스트 period/title 값을 확인해 주세요.');
          }
          final period = periodMatches.first;
          if (!game.availablePeriods.contains(period)) {
            throw FormatException('$name 게임에서 ${period.name} 유형이 꺼져 있습니다.');
          }
          game.quests.add(
            GameQuest(
              title: title.trim(),
              period: period,
              startDate: period == QuestPeriod.weekly ? monday : null,
              endDate: period == QuestPeriod.weekly
                  ? monday.add(const Duration(days: 6))
                  : null,
            ),
          );
        }
        presets.add(game);
      }
      if (!mounted) return;
      setState(
        () => _games
          ..clear()
          ..addAll(presets),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _gamePresetLoadError = error.toString());
    }
  }

  Future<void> _loadScheduleFile() async {
    try {
      final raw = await rootBundle.loadString('assets/calendar_events.json');
      final decoded = jsonDecode(raw);
      if (decoded is! List)
        throw const FormatException('JSON 최상위 값은 일정 배열이어야 합니다.');
      final events = <CalendarEvent>[];
      for (var i = 0; i < decoded.length; i++) {
        final item = decoded[i];
        if (item is! Map<String, dynamic>) {
          throw FormatException(
            '일정 번호 ' + (i + 1).toString() + '은 JSON 객체가 아닙니다.',
          );
        }
        events.add(CalendarEvent.fromJson(item));
      }
      if (!mounted) return;
      setState(() => _events = events);
    } catch (error) {
      if (!mounted) return;
      setState(() => _scheduleLoadError = error.toString());
    }
  }

  Future<void> _addEvent({DateTime? initialDate}) async {
    final event = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => EventEntryScreen(
          initialDate: initialDate ?? _selectedDate,
          gameNames: _games
              .where(
                (game) => game.enabledTypes.contains(GameContentType.schedule),
              )
              .map((game) => game.name)
              .toList(),
        ),
      ),
    );
    if (!mounted || event == null) return;
    setState(() => _events.add(event));
  }

  Future<void> _openGameSearch() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GameSearchScreen(
          games: _games,
          events: _events,
          onEditQuest: _editQuest,
          onDeleteQuest: _deleteQuest,
          onEditEvent: _editEvent,
          onDeleteEvent: _deleteEvent,
        ),
      ),
    );
  }

  Future<void> _editEvent(CalendarEvent original) async {
    final index = _events.indexOf(original);
    if (index < 0) return;
    final updated = await Navigator.push<CalendarEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => EventEntryScreen(
          initialDate: _selectedDate,
          gameNames: _games
              .where(
                (game) => game.enabledTypes.contains(GameContentType.schedule),
              )
              .map((game) => game.name)
              .toList(),
          initialEvent: original,
        ),
      ),
    );
    if (!mounted || updated == null || index >= _events.length) return;
    setState(() => _events[index] = updated);
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    final confirmed = await _confirmDelete('일정', event.title);
    if (!confirmed || !mounted) return;
    setState(() => _events.remove(event));
  }

  Future<void> _editQuest(GameInfo game, GameQuest quest) async {
    final candidates = _games
        .where((item) => item.availablePeriods.isNotEmpty)
        .toList();
    if (!candidates.contains(game)) candidates.add(game);
    final draft = await showDialog<QuestDraft>(
      context: context,
      builder: (_) => QuestEntryDialog(
        games: candidates,
        initialQuest: quest,
        initialGameId: game.id,
      ),
    );
    if (!mounted || draft == null) return;
    final matches = _games.where((item) => item.id == draft.gameId).toList();
    if (matches.isEmpty) return;
    final destination = matches.first;
    setState(() {
      quest.update(
        title: draft.title,
        period: draft.period,
        startDate: draft.startDate,
        endDate: draft.endDate,
      );
      if (!identical(destination, game)) {
        game.quests.remove(quest);
        destination.quests.add(quest);
      }
    });
  }

  Future<void> _deleteQuest(
    GameInfo game,
    GameQuest quest,
    DateTime date,
  ) async {
    if (quest.period == QuestPeriod.daily) {
      final onlyThisDate = await _confirmDailyQuestDelete(quest, date);
      if (onlyThisDate == null || !mounted) return;
      setState(() {
        if (onlyThisDate) {
          quest.excludeDailyDate(date);
        } else {
          game.quests.remove(quest);
        }
      });
      return;
    }
    final confirmed = await _confirmDelete('퀘스트', quest.title);
    if (!confirmed || !mounted) return;
    setState(() => game.quests.remove(quest));
  }

  Future<bool?> _confirmDailyQuestDelete(GameQuest quest, DateTime date) =>
      showDialog<bool>(
        context: context,
        builder: (context) {
          var onlyThisDate = true;
          final dateLabel = '${date.year}년 ${date.month}월 ${date.day}일';
          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('일일 퀘스트 삭제'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('“${quest.title}” 삭제 범위를 선택해 주세요.'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: onlyThisDate,
                    title: const Text('선택한 날짜만 삭제'),
                    subtitle: Text(
                      onlyThisDate
                          ? '$dateLabel에만 표시하지 않습니다.'
                          : '모든 날짜의 반복 퀘스트를 삭제합니다.',
                    ),
                    onChanged: (value) =>
                        setDialogState(() => onlyThisDate = value ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, onlyThisDate),
                  child: const Text('삭제'),
                ),
              ],
            ),
          );
        },
      );

  Future<bool> _confirmDelete(String type, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$type 삭제'),
          content: Text('“$title”을(를) 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _addGame() async {
    final existingNames = _games.map((game) => game.name).toSet();
    final available = gameCatalog
        .where((entry) => !existingNames.contains(entry.name))
        .toList();
    final selected = await showDialog<GameCatalogEntry>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('게임 선택'),
        children: [
          ...available.map(
            (entry) => SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(entry.name),
                subtitle: Text(
                  entry.availablePeriods
                      .map((period) => period.label)
                      .join(' · '),
                ),
              ),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _customGameEntry),
            child: const ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('직접 입력'),
              leading: Icon(Icons.edit_outlined),
            ),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;

    final initialTypes = <GameContentType>{GameContentType.schedule};
    if (identical(selected, _customGameEntry)) {
      initialTypes.addAll(GameContentType.values);
    } else {
      if (selected.availablePeriods.contains(QuestPeriod.daily)) {
        initialTypes.add(GameContentType.daily);
      }
      if (selected.availablePeriods.contains(QuestPeriod.weekly)) {
        initialTypes.add(GameContentType.weekly);
      }
    }

    final draft = await showDialog<GameSetupDraft>(
      context: context,
      builder: (_) => GameSettingsDialog(
        initialName: identical(selected, _customGameEntry) ? '' : selected.name,
        initialAlias: selected.alias,
        initialTypes: initialTypes,
      ),
    );
    if (!mounted || draft == null) return;
    if (_games.any((game) => game.name == draft.name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이미 등록된 게임입니다.')));
      return;
    }

    setState(
      () => _games.add(
        GameInfo(
          name: draft.name,
          alias: draft.alias,
          color: Colors.primaries[_games.length % Colors.primaries.length],
          enabledTypes: draft.enabledTypes,
        ),
      ),
    );
  }

  Future<void> _configureGame() async {
    if (_games.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('먼저 게임을 등록해 주세요.')));
      return;
    }
    final selectedGame = await showDialog<GameInfo>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('설정할 게임 선택'),
        children: _games
            .map(
              (game) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, game),
                child: Text(game.name),
              ),
            )
            .toList(),
      ),
    );
    if (!mounted || selectedGame == null) return;
    final draft = await showDialog<GameSetupDraft>(
      context: context,
      builder: (_) => GameSettingsDialog(
        initialName: selectedGame.name,
        initialAlias: selectedGame.alias,
        initialTypes: selectedGame.enabledTypes,
      ),
    );
    if (!mounted || draft == null) return;
    final hasDuplicateName = _games.any(
      (game) =>
          !identical(game, selectedGame) &&
          game.name.toLowerCase() == draft.name.toLowerCase(),
    );
    if (hasDuplicateName) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이미 등록된 게임 이름입니다.')));
      return;
    }
    final previousName = selectedGame.name;
    setState(() {
      selectedGame.name = draft.name;
      selectedGame.alias = draft.alias;
      selectedGame.enabledTypes
        ..clear()
        ..addAll(draft.enabledTypes);
      for (final event in _events) {
        if (event.gameName == previousName) event.gameName = draft.name;
      }
    });
  }

  Future<void> _addQuest() async {
    if (_games.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('먼저 게임을 등록해 주세요.')));
      await _addGame();
      return;
    }
    final questGames = _games
        .where((game) => game.availablePeriods.isNotEmpty)
        .toList();
    if (questGames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('게임 설정에서 일일 또는 주간 퀘스트를 켜 주세요.')),
      );
      return;
    }
    final draft = await showDialog<QuestDraft>(
      context: context,
      builder: (_) => QuestEntryDialog(games: questGames),
    );
    if (!mounted || draft == null) return;
    final matches = _games.where((game) => game.id == draft.gameId);
    if (matches.isEmpty) return;
    setState(
      () => matches.first.quests.add(
        GameQuest(
          title: draft.title,
          period: draft.period,
          startDate: draft.startDate,
          endDate: draft.endDate,
        ),
      ),
    );
  }

  void _changeMonth(int delta) {
    if (_calendarMode == _CalendarMode.week) {
      final currentWeekStart = _selectedDate.subtract(
        Duration(days: _selectedDate.weekday % 7),
      );
      final targetWeekStart = currentWeekStart.add(Duration(days: delta * 7));
      final targetDate = delta < 0
          ? targetWeekStart.add(const Duration(days: 6))
          : targetWeekStart;
      setState(() {
        _monthSlideDirection = delta >= 0 ? 1 : -1;
        _selectedDate = _dateOnly(targetDate);
        _month = DateTime(targetDate.year, targetDate.month);
      });
      return;
    }

    final next = DateTime(_month.year, _month.month + delta);
    setState(() {
      _monthSlideDirection = delta >= 0 ? 1 : -1;
      _month = next;
      _selectedDate = DateTime(next.year, next.month, 1);
    });
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = _dateOnly(date);
      _month = DateTime(date.year, date.month);
    });
  }

  void _onCalendarDateSelected(DateTime date) {
    _selectDate(date);
    if (_calendarMode == _CalendarMode.full) {
      _showDateDetails(date);
    }
  }

  Future<void> _showDateDetails(DateTime date) async {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final dateLabel =
        '${date.year}년 ${date.month}월 ${date.day}일 (${weekdays[date.weekday - 1]})';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final hasQuests = _games.any(
            (game) => game.quests.any(
              (quest) =>
                  game.enabledTypes.contains(
                    quest.period == QuestPeriod.daily
                        ? GameContentType.daily
                        : GameContentType.weekly,
                  ) &&
                  quest.isApplicableOn(date),
            ),
          );
          final hasEvents = _events.any((event) => event.includes(date));
          return AlertDialog(
            title: Text(dateLabel),
            content: SizedBox(
              width: double.maxFinite,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.68,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (hasEvents)
                        ScheduledEvents(
                          date: date,
                          events: _events,
                          onEdit: (event) async {
                            await _editEvent(event);
                            if (dialogContext.mounted) setDialogState(() {});
                          },
                          onDelete: (event) async {
                            await _deleteEvent(event);
                            if (dialogContext.mounted) setDialogState(() {});
                          },
                        ),
                      if (hasEvents && hasQuests) const SizedBox(height: 8),
                      if (hasQuests)
                        SelectedDayQuests(
                          date: date,
                          games: _games,
                          onChanged: (quest, done) {
                            setState(() => quest.setDoneOn(date, done));
                            setDialogState(() {});
                          },
                          onEdit: (game, quest) async {
                            await _editQuest(game, quest);
                            if (dialogContext.mounted) setDialogState(() {});
                          },
                          onDelete: (game, quest, selectedDate) async {
                            await _deleteQuest(game, quest, selectedDate);
                            if (dialogContext.mounted) setDialogState(() {});
                          },
                        ),
                      if (!hasQuests && !hasEvents)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            '이 날짜에 등록된 퀘스트나 일정이 없습니다.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _addEvent(initialDate: date);
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('일정 추가'),
              ),
            ],
          );
        },
      ),
    );
  }

  String get _monthLabel =>
      _month.year.toString() + '년 ' + _month.month.toString() + '월';
  String get _dateLabel {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return _selectedDate.month.toString() +
        '월 ' +
        _selectedDate.day.toString() +
        '일 (' +
        weekdays[_selectedDate.weekday - 1] +
        ')';
  }

  Widget _selectedDateDetails() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              _dateLabel,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            onPressed: _addEvent,
            tooltip: '일정 추가',
            icon: const Icon(Icons.event_available_outlined),
          ),
          IconButton(
            onPressed: _addQuest,
            tooltip: '퀘스트 추가',
            icon: const Icon(Icons.add_task),
          ),
        ],
      ),
      if (_scheduleLoadError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '일정 JSON을 읽지 못했습니다: ' + _scheduleLoadError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      if (_gamePresetLoadError != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '게임/퀘스트 JSON을 읽지 못했습니다: ' + _gamePresetLoadError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      const SizedBox(height: 8),
      ScheduledEvents(
        date: _selectedDate,
        events: _events,
        onEdit: _editEvent,
        onDelete: _deleteEvent,
      ),
      SelectedDayQuests(
        date: _selectedDate,
        games: _games,
        onChanged: (quest, done) =>
            setState(() => quest.setDoneOn(_selectedDate, done)),
        onEdit: _editQuest,
        onDelete: (game, quest, date) => _deleteQuest(game, quest, date),
      ),
    ],
  );

  Widget _monthSlideTransition(
    Widget child,
    Animation<double> animation,
    int direction,
  ) {
    final isOutgoing = animation.status == AnimationStatus.reverse;
    final horizontalOffset = isOutgoing
        ? -direction.toDouble()
        : direction.toDouble();
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );
    return ClipRect(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(horizontalOffset, 0),
          end: Offset.zero,
        ).animate(curve),
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curve),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _calendar({bool weekOnly = false}) {
    final weekStart = _dateOnly(_selectedDate)
        .subtract(Duration(days: _selectedDate.weekday % 7));
    final calendarKey = weekOnly
        ? 'week:${weekStart.year}-${weekStart.month}-${weekStart.day}'
        : 'month:${_month.year}-${_month.month}';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (child, animation) =>
          _monthSlideTransition(child, animation, _monthSlideDirection),
      child: MonthCalendar(
        key: ValueKey(calendarKey),
        month: _month,
        selectedDate: _selectedDate,
        games: _games,
        events: _events,
        onSelect: _onCalendarDateSelected,
        expanded: _calendarMode != _CalendarMode.month,
        weekOnly: weekOnly,
      ),
    );
  }

  Widget _expandedLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        children: [
          Expanded(
            child: _calendarSwipeRegion(SizedBox.expand(child: _calendar())),
          ),
        ],
      ),
    );
  }

  Widget _collapsedLayout() => ScrollConfiguration(
    behavior: const _NoStretchScrollBehavior(),
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _calendarSwipeRegion(_calendar()),
          const SizedBox(height: 12),
          _selectedDateDetails(),
        ],
      ),
    ),
  );

  Widget _weekLayout() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
    child: Column(
      children: [
        SizedBox(
          height: 140,
          child: _calendarSwipeRegion(_calendar(weekOnly: true)),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: _selectedDateDetails(),
          ),
        ),
      ],
    ),
  );

  Future<void> _runDrawerAction(Future<void> Function() action) async {
    Navigator.pop(context);
    await action();
  }

  Widget _menuDrawer() => Drawer(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF485CCB)),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                '게임 퀘스트 캘린더',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videogame_asset_outlined),
            title: const Text('게임 추가'),
            onTap: () => _runDrawerAction(_addGame),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('게임 설정'),
            onTap: () => _runDrawerAction(_configureGame),
          ),
        ],
      ),
    ),
  );

  Widget _topBar() => AppBar(
    centerTitle: true,
    leading: Builder(
      builder: (context) => IconButton(
        tooltip: '메뉴 열기',
        onPressed: () => Scaffold.of(context).openDrawer(),
        icon: const Icon(Icons.menu),
      ),
    ),
    title: AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeInOutCubic,
      switchOutCurve: Curves.easeInOutCubic,
      transitionBuilder: (child, animation) =>
          _monthSlideTransition(child, animation, _monthSlideDirection),
      child: Text(
        _monthLabel,
        key: ValueKey(_monthLabel),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => _selectDate(DateTime.now()),
        child: const Text('오늘'),
      ),
      IconButton(
        onPressed: _openGameSearch,
        tooltip: '게임 및 일정 검색',
        icon: const Icon(Icons.search),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: false,
    drawer: _menuDrawer(),
    body: SafeArea(
      child: Column(
        children: [
          SizedBox(height: kToolbarHeight, child: _topBar()),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 650),
                switchInCurve: Curves.easeInOutCubic,
                switchOutCurve: Curves.easeInOutCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, 0.02),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_calendarMode),
                  child: switch (_calendarMode) {
                    _CalendarMode.full => _expandedLayout(),
                    _CalendarMode.month => _collapsedLayout(),
                    _CalendarMode.week => _weekLayout(),
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

const _customGameEntry = GameCatalogEntry(
  name: '',
  availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
);
DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

class _NoStretchScrollBehavior extends ScrollBehavior {
  const _NoStretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
