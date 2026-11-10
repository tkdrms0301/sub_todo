import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/quest.dart';
import 'game_avatar.dart';

bool _isQuestTypeEnabled(GameInfo game, GameQuest quest) =>
    game.enabledTypes.contains(
      quest.period == QuestPeriod.daily
          ? GameContentType.daily
          : GameContentType.weekly,
    );

class SelectedDayQuests extends StatelessWidget {
  const SelectedDayQuests({
    required this.date,
    required this.games,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
    super.key,
  });

  final DateTime date;
  final List<GameInfo> games;
  final void Function(GameQuest, bool) onChanged;
  final void Function(GameInfo, GameQuest) onEdit;
  final void Function(GameInfo, GameQuest, DateTime) onDelete;

  String _rangeLabel(GameQuest quest) {
    String dateText(DateTime value) =>
        value.month.toString() + '/' + value.day.toString();
    final start = quest.occurrenceStartOn(date);
    final end = quest.occurrenceEndOn(date);
    if (start == null || end == null) return '이번 주';
    return dateText(start) + ' ~ ' + dateText(end);
  }

  @override
  Widget build(BuildContext context) {
    final active = games
        .where(
          (game) => game.quests.any(
            (quest) =>
                _isQuestTypeEnabled(game, quest) && quest.isApplicableOn(date),
          ),
        )
        .toList();
    if (active.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              games.isEmpty ? '게임과 퀘스트를 등록해 보세요.' : '이 날짜에 등록된 퀘스트가 없습니다.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ),
      );
    }

    final sections = <Widget>[];
    for (final period in [QuestPeriod.weekly, QuestPeriod.daily]) {
      final periodGames = <(GameInfo, List<GameQuest>)>[];
      for (final game in active) {
        final quests = game.quests
            .where(
              (quest) =>
                  quest.period == period &&
                  _isQuestTypeEnabled(game, quest) &&
                  quest.isApplicableOn(date),
            )
            .toList();
        if (quests.isNotEmpty) periodGames.add((game, quests));
      }
      if (periodGames.isEmpty) continue;
      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${period.label} 퀘스트',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
      for (final (game, quests) in periodGames) {
        final done = quests.where((quest) => quest.isDoneOn(date)).length;
        final allDone = done == quests.length;
        sections.add(
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: allDone ? Colors.grey.shade500 : null,
                          ),
                        ),
                      ),
                      Text(
                        '$done/${quests.length} 완료',
                        style: TextStyle(
                          color: allDone
                              ? Colors.green.shade700
                              : Colors.grey.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                ...quests.map((quest) {
                  final isDone = quest.isDoneOn(date);
                  return ListTile(
                    dense: true,
                    leading: _GameCompletionButton(
                      game: game,
                      isDone: isDone,
                      onTap: () => onChanged(quest, !isDone),
                    ),
                    title: Text(
                      quest.title,
                      style: TextStyle(
                        color: isDone ? Colors.grey.shade500 : null,
                      ),
                    ),
                    subtitle: Text(
                      quest.period.label +
                          ' 퀘스트' +
                          (quest.period == QuestPeriod.weekly
                              ? ' · ' + _rangeLabel(quest)
                              : ''),
                      style: TextStyle(
                        color: isDone ? Colors.grey.shade500 : null,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '퀘스트 수정',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                          color: isDone ? Colors.grey.shade400 : null,
                          onPressed: () => onEdit(game, quest),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                        ),
                        IconButton(
                          tooltip: '퀘스트 삭제',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                          color: isDone ? Colors.grey.shade400 : null,
                          onPressed: () => onDelete(game, quest, date),
                          icon: const Icon(Icons.delete_outline, size: 20),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      }
    }
    return Column(children: sections);
  }
}

class _GameCompletionButton extends StatelessWidget {
  const _GameCompletionButton({
    required this.game,
    required this.isDone,
    required this.onTap,
  });

  final GameInfo game;
  final bool isDone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: isDone ? '${game.name} 완료 취소' : '${game.name} 완료 표시',
    child: InkWell(
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: isDone ? 0.38 : 1,
              child: GameAvatar(game: game, radius: 19),
            ),
            if (isDone)
              Container(
                width: 25,
                height: 25,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  size: 21,
                  color: Colors.green.shade700,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
