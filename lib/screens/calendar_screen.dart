import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_data_backup.dart';
import '../models/calendar_event.dart';
import '../models/game.dart';
import '../models/quest.dart';
import '../utils/game_icon.dart';
import '../widgets/month_calendar.dart';
import '../widgets/game_avatar.dart';
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

enum _GameManagementActionType { edit, remove, add }

class _GameManagementAction {
  const _GameManagementAction(this.type, {this.game});

  final _GameManagementActionType type;
  final GameInfo? game;
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  static const _localDataKey = 'sub_todo_app_data_v1';

  final List<GameInfo> _games = [];
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  List<CalendarEvent> _events = [];
  Future<void> _saveQueue = Future<void>.value();
  bool _isLoadingData = true;
  String? _dataLoadWarning;
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
    WidgetsBinding.instance.addObserver(this);
    _initializeData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isLoadingData &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      // Each edit is saved immediately; persist once more when leaving the app
      // to cover cases where Android backgrounds the process during a write.
      _saveAppData();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initializeData() async {
    var shouldSaveDefaults = false;
    var shouldSaveMigratedIcons = false;
    try {
      final saved = await _preferences.getString(_localDataKey);
      if (saved == null) {
        await _loadDefaultData();
        shouldSaveDefaults = true;
      } else {
        try {
          final backup = AppDataBackup.decode(saved);
          shouldSaveMigratedIcons = await _fillMissingDefaultGameIcons(
            backup.games,
          );
          if (!mounted) return;
          setState(() {
            _games
              ..clear()
              ..addAll(backup.games);
            _events = backup.events;
          });
        } catch (error) {
          _dataLoadWarning =
              '저장 데이터를 불러오지 못해 기본 데이터로 시작합니다. 백업 파일에서 복원해 주세요. ($error)';
          await _loadDefaultData();
        }
      }
    } catch (error) {
      _dataLoadWarning = '기기 저장소를 읽지 못했습니다. ($error)';
      await _loadDefaultData();
    } finally {
      if (mounted) setState(() => _isLoadingData = false);
    }
    if (!mounted) return;
    if ((shouldSaveDefaults || shouldSaveMigratedIcons) &&
        _dataLoadWarning == null) {
      await _saveAppData();
    }
  }

  Future<bool> _fillMissingDefaultGameIcons(Iterable<GameInfo> games) async {
    var changed = false;
    for (final game in games) {
      if (game.iconBase64 != null && game.iconBase64!.isNotEmpty) continue;
      final catalogEntry = gameCatalog
          .where((entry) => entry.name.toLowerCase() == game.name.toLowerCase())
          .firstOrNull;
      final iconAsset = catalogEntry?.iconAsset;
      if (iconAsset == null) continue;
      try {
        game.iconBase64 = await loadGameIconAsset(iconAsset);
        changed = true;
      } catch (_) {
        // Keep the game's generic icon if a bundled icon cannot be read.
      }
    }
    return changed;
  }

  Future<void> _loadDefaultData() async {
    await Future.wait([_loadScheduleFile(), _loadGamePresets()]);
  }

  Future<void> _saveAppData() {
    final contents = AppDataBackup(games: _games, events: _events).encode();
    _saveQueue = _saveQueue.catchError((Object _) {}).then((_) async {
      try {
        await _preferences.setString(_localDataKey, contents);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('기기 저장에 실패했습니다: $error')));
        }
      }
    });
    return _saveQueue;
  }

  Future<void> _exportBackup() async {
    try {
      await _saveAppData();
      final now = DateTime.now();
      final date =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}';
      final result = await FilePicker.saveFile(
        dialogTitle: '백업 파일 저장',
        fileName: 'sub_todo_backup_$date.json',
        bytes: Uint8List.fromList(
          utf8.encode(AppDataBackup(games: _games, events: _events).encode()),
        ),
      );
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('백업 파일을 저장했습니다.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('백업 파일 저장에 실패했습니다: $error')));
    }
  }

  Future<void> _importBackup({bool confirmReplace = true}) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final backup = AppDataBackup.decode(
        utf8.decode(await file.readAsBytes()),
      );
      await _fillMissingDefaultGameIcons(backup.games);
      if (!mounted) return;
      final questCount = backup.games.fold<int>(
        0,
        (count, game) => count + game.quests.length,
      );
      if (confirmReplace) {
        final shouldRestore = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('백업 복원'),
            content: Text(
              '게임 ${backup.games.length}개, 퀘스트 $questCount개, '
              '일정 ${backup.events.length}개를 복원합니다. '
              '현재 앱 데이터는 백업 내용으로 바뀝니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('복원'),
              ),
            ],
          ),
        );
        if (!mounted || shouldRestore != true) return;
      }
      if (!mounted) return;
      setState(() {
        _games
          ..clear()
          ..addAll(backup.games);
        _events = backup.events;
        _dataLoadWarning = null;
      });
      await _saveAppData();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('백업을 복원했습니다.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('백업 파일을 읽지 못했습니다: $error')));
    }
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
        final iconAsset = value['iconAsset'];
        final iconBase64 = iconAsset is String
            ? await loadGameIconAsset(iconAsset)
            : null;
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
          iconBase64: iconBase64,
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
    await _saveAppData();
  }

  Future<void> _openGameSearch() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GameSearchScreen(
          games: _games,
          events: _events,
          onDataChanged: _saveAppData,
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
    await _saveAppData();
  }

  Future<void> _deleteEvent(CalendarEvent event) async {
    final confirmed = await _confirmDelete('일정', event.title);
    if (!confirmed || !mounted) return;
    setState(() => _events.remove(event));
    await _saveAppData();
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
    await _saveAppData();
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
      await _saveAppData();
      return;
    }
    final confirmed = await _confirmDelete('퀘스트', quest.title);
    if (!confirmed || !mounted) return;
    setState(() => game.quests.remove(quest));
    await _saveAppData();
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
    final selected = await showDialog<GameCatalogEntry>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('게임 추가'),
        children: [
          ...gameCatalog.map(
            (entry) => _gameCatalogOption(dialogContext, entry),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, _customGameEntry),
            child: Row(
              children: [
                _customGameIcon(),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text('그 외 게임 직접 추가'), Text('게임 이름과 아이콘 설정')],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!mounted || selected == null) return;

    if (identical(selected, _customGameEntry)) {
      await _addCustomGame();
      return;
    }
    final duplicate = _games.any(
      (game) => game.name.toLowerCase() == selected.name.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 등록된 게임입니다. 게임 관리에서 수정할 수 있어요.')),
      );
      return;
    }

    final enabledTypes = <GameContentType>{GameContentType.schedule};
    if (selected.availablePeriods.contains(QuestPeriod.daily)) {
      enabledTypes.add(GameContentType.daily);
    }
    if (selected.availablePeriods.contains(QuestPeriod.weekly)) {
      enabledTypes.add(GameContentType.weekly);
    }
    final iconBase64 = selected.iconAsset == null
        ? null
        : await loadGameIconAsset(selected.iconAsset!);
    if (!mounted) return;

    setState(
      () => _games.add(
        GameInfo(
          name: selected.name,
          alias: selected.alias,
          iconBase64: iconBase64,
          color: Colors.primaries[_games.length % Colors.primaries.length],
          enabledTypes: enabledTypes,
        ),
      ),
    );
    await _saveAppData();
  }

  Future<void> _addCustomGame() async {
    final draft = await showDialog<GameSetupDraft>(
      context: context,
      builder: (_) => GameSettingsDialog(
        initialName: '',
        initialTypes: {...GameContentType.values},
        allowCustomIcon: true,
      ),
    );
    if (!mounted || draft == null) return;
    if (_games.any(
      (game) => game.name.toLowerCase() == draft.name.toLowerCase(),
    )) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('이미 등록된 게임입니다.')));
      return;
    }
    final catalogEntry = gameCatalog
        .where((entry) => entry.name.toLowerCase() == draft.name.toLowerCase())
        .firstOrNull;
    final iconBase64 =
        draft.iconBase64 ??
        (catalogEntry?.iconAsset == null
            ? null
            : await loadGameIconAsset(catalogEntry!.iconAsset!));
    if (!mounted) return;
    setState(
      () => _games.add(
        GameInfo(
          name: draft.name,
          alias: draft.alias,
          iconBase64: iconBase64,
          color: Colors.primaries[_games.length % Colors.primaries.length],
          enabledTypes: draft.enabledTypes,
        ),
      ),
    );
    await _saveAppData();
  }

  Widget _gameCatalogOption(
    BuildContext dialogContext,
    GameCatalogEntry entry,
  ) {
    final isSelected = _games.any(
      (game) => game.name.toLowerCase() == entry.name.toLowerCase(),
    );
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(dialogContext, entry),
      child: Row(
        children: [
          _catalogGameIcon(entry, isSelected),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name),
                Text(
                  entry.availablePeriods
                      .map((period) => period.label)
                      .join(' · '),
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _catalogGameIcon(GameCatalogEntry entry, bool selected) => SizedBox(
    width: 48,
    height: 48,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? Colors.green.shade600 : Colors.grey.shade400,
                width: selected ? 2.5 : 1,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: entry.iconAsset == null
                  ? const Icon(Icons.videogame_asset_outlined)
                  : Image.asset(
                      entry.iconAsset!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const Icon(Icons.videogame_asset_outlined),
                    ),
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 19,
            height: 19,
            decoration: BoxDecoration(
              color: selected ? Colors.green.shade600 : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.green.shade600 : Colors.grey.shade400,
              ),
            ),
            child: Icon(
              selected ? Icons.check : Icons.add,
              size: 14,
              color: selected ? Colors.white : Colors.grey.shade700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _customGameIcon() => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade400),
    ),
    child: const Icon(Icons.edit_outlined),
  );

  Future<void> _removeGameSelection(GameInfo game) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('게임 선택 해제'),
        content: Text(
          '${game.name}의 퀘스트 ${game.quests.length}개를 삭제할까요? '
          '이 게임에 연결된 일정은 유지됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('선택 해제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _games.remove(game));
    await _saveAppData();
  }

  Future<void> _configureGame() async {
    final action = await showDialog<_GameManagementAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('게임 선택 및 관리'),
        content: SizedBox(
          width: 380,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 440),
            child: _games.isEmpty
                ? const Center(child: Text('등록된 게임이 없습니다.'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: _games.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final game = _games[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: GameAvatar(game: game, radius: 20),
                        title: Text(game.name),
                        subtitle: Text(game.alias),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '수정',
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                _GameManagementAction(
                                  _GameManagementActionType.edit,
                                  game: game,
                                ),
                              ),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '삭제',
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                _GameManagementAction(
                                  _GameManagementActionType.remove,
                                  game: game,
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(
              dialogContext,
              const _GameManagementAction(_GameManagementActionType.add),
            ),
            icon: const Icon(Icons.add),
            label: const Text('게임 추가'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action.type) {
      case _GameManagementActionType.add:
        await _addGame();
        break;
      case _GameManagementActionType.edit:
        final game = action.game;
        if (game != null) await _editGame(game);
        break;
      case _GameManagementActionType.remove:
        final game = action.game;
        if (game != null) await _removeGameSelection(game);
        break;
    }
  }

  Future<void> _editGame(GameInfo selectedGame) async {
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
    await _saveAppData();
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
    await _saveAppData();
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
                            _saveAppData();
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

  String get _monthLabel => _month.month.toString() + '월';
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
      if (_dataLoadWarning != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _dataLoadWarning!,
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
        onChanged: (quest, done) {
          setState(() => quest.setDoneOn(_selectedDate, done));
          _saveAppData();
        },
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
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF485CCB)),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                '할 건 해야지',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videogame_asset_outlined),
            title: const Text('게임 관리'),
            onTap: () => _runDrawerAction(_configureGame),
          ),
          ExpansionTile(
            leading: const Icon(Icons.backup_outlined),
            title: const Text('백업'),
            children: [
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 16),
                title: const Text('불러오기'),
                onTap: () => _runDrawerAction(_importBackup),
              ),
              ListTile(
                contentPadding: const EdgeInsets.only(left: 72, right: 16),
                title: const Text('내보내기'),
                onTap: () => _runDrawerAction(_exportBackup),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _topBar() => AppBar(
    centerTitle: false,
    titleSpacing: 0,
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
  Widget build(BuildContext context) => _isLoadingData
      ? const Scaffold(body: Center(child: CircularProgressIndicator()))
      : Scaffold(
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
