import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_data_backup.dart';
import '../models/game.dart';
import '../models/quest.dart';
import '../utils/game_icon.dart';

class FirstRunSetupScreen extends StatefulWidget {
  const FirstRunSetupScreen({
    required this.onComplete,
    this.existingData,
    super.key,
  });

  final VoidCallback onComplete;
  final AppDataBackup? existingData;

  @override
  State<FirstRunSetupScreen> createState() => _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends State<FirstRunSetupScreen> {
  static const _localDataKey = 'sub_todo_app_data_v1';
  static const _setupCompletedKey = 'sub_todo_initial_setup_completed_v1';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final PageController _pageController = PageController();
  final Set<String> _selectedGameNames = {};
  final Map<String, String> _gameIconData = {};
  List<GameInfo> _gameTemplates = [];
  AppDataBackup? _selectedBackup;
  bool _backupSelectedFromFile = false;
  bool _loading = true;
  bool _saving = false;
  int _pageIndex = 0;

  static const _pageTitles = ['앱 소개', '백업 불러오기', '게임 선택', '시작 준비 완료'];

  @override
  void initState() {
    super.initState();
    _loadGameTemplates();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadGameTemplates() async {
    try {
      final raw = await rootBundle.loadString('assets/game_quests.json');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rawGames = decoded['games'] as List<dynamic>;
      final today = DateTime.now();
      final monday = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(Duration(days: today.weekday - DateTime.monday));
      final games = <GameInfo>[];
      for (final value in rawGames) {
        final item = Map<String, dynamic>.from(value as Map);
        final name = item['name'] as String;
        final iconAsset = item['iconAsset'];
        final iconBase64 = iconAsset is String
            ? await loadGameIconAsset(iconAsset)
            : null;
        final types = (item['types'] as List<dynamic>)
            .map((value) => GameContentType.values.byName(value as String))
            .toSet();
        final game = GameInfo(
          name: name,
          alias: item['alias'] as String?,
          iconBase64: iconBase64,
          color: Colors.primaries[games.length % Colors.primaries.length],
          enabledTypes: types,
        );
        for (final rawQuest in item['quests'] as List<dynamic>? ?? const []) {
          final quest = Map<String, dynamic>.from(rawQuest as Map);
          final period = QuestPeriod.values.byName(quest['period'] as String);
          game.quests.add(
            GameQuest(
              title: quest['title'] as String,
              period: period,
              startDate: period == QuestPeriod.weekly ? monday : null,
              endDate: period == QuestPeriod.weekly
                  ? monday.add(const Duration(days: 6))
                  : null,
            ),
          );
        }
        games.add(game);
      }
      if (mounted) {
        setState(() {
          _gameTemplates = games;
          _selectedBackup = widget.existingData;
          for (final template in games) {
            final saved = widget.existingData?.games
                .where((game) => game.name == template.name)
                .firstOrNull;
            final icon = saved?.iconBase64 ?? template.iconBase64;
            if (icon != null) _gameIconData[template.name] = icon;
          }
          for (final game in widget.existingData?.games ?? const <GameInfo>[]) {
            if (game.iconBase64 != null && game.iconBase64!.isNotEmpty) {
              _gameIconData[game.name] = game.iconBase64!;
            }
          }
          _selectedGameNames.addAll(
            widget.existingData?.games
                    .where(
                      (saved) => games.any((item) => item.name == saved.name),
                    )
                    .map((saved) => saved.name) ??
                const <String>[],
          );
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('게임 목록을 불러오지 못했습니다: $error');
    }
  }

  Future<void> _importBackup() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final backup = AppDataBackup.decode(
        utf8.decode(await file.readAsBytes()),
      );
      if (!mounted) return;
      setState(() {
        _selectedBackup = backup;
        _backupSelectedFromFile = true;
        _gameIconData
          ..clear()
          ..addEntries(
            _gameTemplates
                .where((game) => game.iconBase64 != null)
                .map((game) => MapEntry(game.name, game.iconBase64!)),
          )
          ..addEntries(
            backup.games
                .where(
                  (game) =>
                      game.iconBase64 != null && game.iconBase64!.isNotEmpty,
                )
                .map((game) => MapEntry(game.name, game.iconBase64!)),
          );
        _selectedGameNames
          ..clear()
          ..addAll(
            backup.games
                .where(
                  (saved) =>
                      _gameTemplates.any((item) => item.name == saved.name),
                )
                .map((saved) => saved.name),
          );
      });
      _showMessage(
        '게임 ${backup.games.length}개와 일정 ${backup.events.length}개를 불러왔어요.',
      );
    } catch (error) {
      if (mounted) _showMessage('백업 파일을 읽지 못했습니다: $error');
    }
  }

  Future<void> _selectGameIcon(GameInfo game) async {
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        _showMessage('20MB 이하의 이미지 파일을 선택해 주세요.');
        return;
      }
      final optimized = await prepareGameIcon(bytes);
      if (!mounted) return;
      setState(() => _gameIconData[game.name] = optimized);
    } catch (error) {
      if (mounted) _showMessage('게임 아이콘을 불러오지 못했습니다: $error');
    }
  }

  Future<void> _skipSetup() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      // A new installation that skips setup starts with an empty calendar;
      // existing users keep the data already saved on their device.
      final savedData = await _preferences.getString(_localDataKey);
      if (savedData == null) {
        await _preferences.setString(
          _localDataKey,
          const AppDataBackup(games: [], events: []).encode(),
        );
      }
      await _preferences.setBool(_setupCompletedKey, true);
      if (mounted) widget.onComplete();
    } catch (error) {
      if (mounted) _showMessage('초기 설정을 건너뛰지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _finishSetup() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final existingGames = _selectedBackup?.games ?? const <GameInfo>[];
      final games = existingGames
          .where(
            (saved) =>
                !_gameTemplates.any((template) => template.name == saved.name),
          )
          .toList();
      final existingNames = <String>{};
      for (final template in _gameTemplates) {
        if (_selectedGameNames.contains(template.name)) {
          final existing = existingGames.where(
            (saved) => saved.name.toLowerCase() == template.name.toLowerCase(),
          );
          final game = existing.isEmpty ? template : existing.first;
          game.iconBase64 = _gameIconData[template.name] ?? game.iconBase64;
          if (existingNames.add(game.name.toLowerCase())) games.add(game);
        }
      }
      final events = [...?_selectedBackup?.events];
      final contents = AppDataBackup(games: games, events: events).encode();
      await _preferences.setString(_localDataKey, contents);
      await _preferences.setBool(_setupCompletedKey, true);
      if (!mounted) return;
      widget.onComplete();
    } catch (error) {
      if (mounted) _showMessage('초기 설정을 저장하지 못했습니다: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _pageTitles.length) return;
    setState(() => _pageIndex = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  int get _restoredCustomGameCount =>
      _selectedBackup?.games
          .where(
            (saved) =>
                !_gameTemplates.any((template) => template.name == saved.name),
          )
          .length ??
      0;

  Widget _buildIntroPage() => ListView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
    children: [
      const SizedBox(height: 28),
      Center(
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Icon(
            Icons.calendar_month_rounded,
            size: 62,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
      const SizedBox(height: 32),
      Text(
        '할 건 해야지',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 14),
      Text(
        '서브컬처 게임의 일일·주간 퀘스트와 게임 일정을 한곳에서 관리해요.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 28),
      const _IntroFeature(
        icon: Icons.check_circle_outline,
        title: '퀘스트 완료 기록',
        detail: '매일·매주 할 일을 체크하고 달력에서 확인해요.',
      ),
      const _IntroFeature(
        icon: Icons.event_note_outlined,
        title: '게임 일정 관리',
        detail: '업데이트와 이벤트 기간도 함께 기록해요.',
      ),
      const _IntroFeature(
        icon: Icons.backup_outlined,
        title: '백업과 복원',
        detail: 'JSON 파일로 데이터를 보관하고 새 기기에서 불러와요.',
      ),
    ],
  );

  Widget _buildBackupPage() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
    children: [
      Text(
        '저장해 둔 백업이 있나요?',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('백업 파일을 불러오면 게임, 퀘스트, 일정과 완료 기록을 복원합니다.'),
      const SizedBox(height: 24),
      Card(
        child: ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: Text(
            _backupSelectedFromFile ? '다른 백업 파일 선택' : '백업 JSON 파일 선택',
          ),
          subtitle: Text(
            _selectedBackup == null
                ? '파일이 없어도 다음 단계로 진행할 수 있어요.'
                : _backupSelectedFromFile
                ? '게임 ${_selectedBackup!.games.length}개 · '
                      '일정 ${_selectedBackup!.events.length}개 불러옴'
                : '현재 저장된 데이터 유지 · '
                      '게임 ${_selectedBackup!.games.length}개 · '
                      '일정 ${_selectedBackup!.events.length}개',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: _importBackup,
        ),
      ),
      const SizedBox(height: 12),
      if (_selectedBackup != null)
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            leading: const Icon(Icons.check_circle_outline),
            title: Text(
              _backupSelectedFromFile ? '백업 파일을 준비했어요' : '기존 데이터를 유지해요',
            ),
            subtitle: const Text('다음 단계에서 게임을 확인하고 시작할 수 있어요.'),
          ),
        ),
    ],
  );

  Widget _buildGamePage() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
    children: [
      Text(
        '관리할 게임을 골라주세요',
        style: Theme.of(context).textTheme.headlineSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      const Text('선택한 게임의 기본 퀘스트가 등록됩니다. 게임 아이콘을 누르면 휴대폰에서 이미지를 골라 설정할 수 있어요.'),
      const SizedBox(height: 16),
      ..._gameTemplates.map(
        (game) => Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: CheckboxListTile(
            value: _selectedGameNames.contains(game.name),
            title: Text(game.name),
            subtitle: Text(game.quests.map((quest) => quest.title).join(' · ')),
            secondary: _gameIconButton(game),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                _selectedGameNames.add(game.name);
              } else {
                _selectedGameNames.remove(game.name);
              }
            }),
          ),
        ),
      ),
      if (_restoredCustomGameCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '목록에 없는 게임 $_restoredCustomGameCount개도 백업에서 함께 복원됩니다.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );

  Widget _gameIconButton(GameInfo game) {
    final icon = _gameIconData[game.name] ?? game.iconBase64;
    return Tooltip(
      message: '눌러서 ${game.name} 아이콘 선택',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => _selectGameIcon(game),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CircleAvatar(
                  backgroundColor: game.color.withValues(alpha: 0.2),
                  child: icon == null
                      ? Icon(Icons.videogame_asset, color: game.color)
                      : ClipOval(
                          child: Image.memory(
                            base64Decode(icon),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.videogame_asset, color: game.color),
                          ),
                        ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinishPage() {
    final totalGames = _selectedGameNames.length + _restoredCustomGameCount;
    final eventCount = _selectedBackup?.events.length ?? 0;
    final backupDescription = _selectedBackup == null
        ? '백업 없이 새로 시작'
        : _backupSelectedFromFile
        ? '백업 데이터 ${_selectedBackup!.games.length}개 게임, $eventCount개 일정'
        : '기존 데이터 ${_selectedBackup!.games.length}개 게임, $eventCount개 일정 유지';
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: [
        Center(
          child: Icon(
            Icons.check_circle_rounded,
            size: 76,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '준비가 끝났어요',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text('설정을 저장하고 캘린더를 시작할게요.', textAlign: TextAlign.center),
        const SizedBox(height: 28),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.backup_outlined),
                title: const Text('데이터'),
                subtitle: Text(backupDescription),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.videogame_asset_outlined),
                title: const Text('선택한 게임'),
                subtitle: Text('$totalGames개'),
              ),
              if (_selectedGameNames.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(72, 0, 16, 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_selectedGameNames.join(' · ')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: _pageIndex == 0
          ? null
          : IconButton(
              tooltip: '이전',
              onPressed: _saving ? null : () => _goToPage(_pageIndex - 1),
              icon: const Icon(Icons.arrow_back),
            ),
      title: Text(_pageTitles[_pageIndex]),
      actions: [
        TextButton(
          onPressed: _saving ? null : _skipSetup,
          child: const Text('건너뛰기'),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Text('${_pageIndex + 1} / ${_pageTitles.length}'),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: LinearProgressIndicator(
          value: (_pageIndex + 1) / _pageTitles.length,
          minHeight: 3,
        ),
      ),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildIntroPage(),
                      _buildBackupPage(),
                      _buildGamePage(),
                      _buildFinishPage(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : _pageIndex == _pageTitles.length - 1
                          ? _finishSetup
                          : () => _goToPage(_pageIndex + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _pageIndex == 1 && _selectedBackup == null
                                    ? '백업 없이 계속'
                                    : _pageIndex == _pageTitles.length - 1
                                    ? '캘린더 시작하기'
                                    : '다음',
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}

class _IntroFeature extends StatelessWidget {
  const _IntroFeature({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(detail),
            ],
          ),
        ),
      ],
    ),
  );
}
