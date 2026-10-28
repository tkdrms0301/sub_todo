import 'package:flutter/material.dart';

import 'quest.dart';

enum GameContentType { daily, weekly, schedule }

extension GameContentTypeLabel on GameContentType {
  String get label {
    switch (this) {
      case GameContentType.daily:
        return '일일 퀘스트';
      case GameContentType.weekly:
        return '주간 퀘스트';
      case GameContentType.schedule:
        return '일정';
    }
  }
}

class GameInfo {
  GameInfo({
    required this.name,
    String? alias,
    required this.color,
    required Set<GameContentType> enabledTypes,
  }) : id = DateTime.now().microsecondsSinceEpoch.toString(),
       alias = alias == null || alias.trim().isEmpty ? name : alias.trim(),
       enabledTypes = {...enabledTypes};

  final String id;
  String name;
  String alias;
  final Color color;
  final Set<GameContentType> enabledTypes;
  final List<GameQuest> quests = [];

  List<QuestPeriod> get availablePeriods => [
    if (enabledTypes.contains(GameContentType.daily)) QuestPeriod.daily,
    if (enabledTypes.contains(GameContentType.weekly)) QuestPeriod.weekly,
  ];
}

class GameCatalogEntry {
  const GameCatalogEntry({
    required this.name,
    this.alias,
    required this.availablePeriods,
  });

  final String name;
  final String? alias;
  final List<QuestPeriod> availablePeriods;
}

const gameCatalog = <GameCatalogEntry>[
  GameCatalogEntry(
    name: '원신',
    alias: '원신',
    availablePeriods: [QuestPeriod.daily],
  ),
  GameCatalogEntry(
    name: '명조: 워더링 웨이브',
    alias: '명조',
    availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
  ),
  GameCatalogEntry(
    name: '블루 아카이브',
    alias: '블아',
    availablePeriods: [QuestPeriod.daily],
  ),
  GameCatalogEntry(
    name: '승리의 여신: 니케',
    alias: '니케',
    availablePeriods: [QuestPeriod.daily],
  ),
  GameCatalogEntry(
    name: '젠레스 존 제로',
    alias: '젠존제',
    availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
  ),
  GameCatalogEntry(
    name: '붕괴: 스타레일',
    alias: '붕스',
    availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
  ),
];
