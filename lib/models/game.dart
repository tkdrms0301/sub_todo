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
    String? id,
    required this.name,
    String? alias,
    this.iconBase64,
    required this.color,
    required Set<GameContentType> enabledTypes,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       alias = alias == null || alias.trim().isEmpty ? name : alias.trim(),
       enabledTypes = {...enabledTypes};

  final String id;
  String name;
  String alias;
  String? iconBase64;
  final Color color;
  final Set<GameContentType> enabledTypes;
  final List<GameQuest> quests = [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'alias': alias,
    if (iconBase64 != null && iconBase64!.isNotEmpty) 'iconBase64': iconBase64,
    'color': color.toARGB32(),
    'enabledTypes': enabledTypes.map((type) => type.name).toList()..sort(),
    'quests': quests.map((quest) => quest.toJson()).toList(),
  };

  factory GameInfo.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('게임 이름이 비어 있습니다.');
    }
    final rawTypes = json['enabledTypes'];
    if (rawTypes is! List || rawTypes.any((value) => value is! String)) {
      throw FormatException('$name 게임의 enabledTypes가 올바르지 않습니다.');
    }
    final types = <GameContentType>{};
    for (final typeName in rawTypes.cast<String>()) {
      final matches = GameContentType.values
          .where((type) => type.name == typeName)
          .toList();
      if (matches.isEmpty) {
        throw FormatException('$name 게임의 알 수 없는 유형: $typeName');
      }
      types.add(matches.first);
    }
    final rawQuests = json['quests'] ?? const [];
    if (rawQuests is! List || rawQuests.any((value) => value is! Map)) {
      throw FormatException('$name 게임의 퀘스트 목록이 올바르지 않습니다.');
    }
    final colorValue = json['color'];
    final color = colorValue is int ? Color(colorValue) : Colors.primaries[0];
    final idValue = json['id'];
    final game = GameInfo(
      id: idValue is String && idValue.isNotEmpty ? idValue : null,
      name: name.trim(),
      alias: json['alias'] is String ? json['alias'] as String : null,
      iconBase64: json['iconBase64'] is String
          ? json['iconBase64'] as String
          : null,
      color: color,
      enabledTypes: types,
    );
    game.quests.addAll(
      rawQuests.map(
        (value) => GameQuest.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
    return game;
  }

  List<QuestPeriod> get availablePeriods => [
    if (enabledTypes.contains(GameContentType.daily)) QuestPeriod.daily,
    if (enabledTypes.contains(GameContentType.weekly)) QuestPeriod.weekly,
  ];
}

class GameCatalogEntry {
  const GameCatalogEntry({
    required this.name,
    this.alias,
    this.iconAsset,
    required this.availablePeriods,
  });

  final String name;
  final String? alias;
  final String? iconAsset;
  final List<QuestPeriod> availablePeriods;
}

const gameCatalog = <GameCatalogEntry>[
  GameCatalogEntry(
    name: '원신',
    alias: '원신',
    iconAsset: 'assets/game_icons/genshin.png',
    availablePeriods: [QuestPeriod.daily],
  ),
  GameCatalogEntry(
    name: '명조: 워더링 웨이브',
    alias: '명조',
    iconAsset: 'assets/game_icons/wuthering_waves.png',
    availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
  ),
  GameCatalogEntry(
    name: '블루 아카이브',
    alias: '블아',
    iconAsset: 'assets/game_icons/blue_archive.png',
    availablePeriods: [QuestPeriod.daily],
  ),
  GameCatalogEntry(
    name: '승리의 여신: 니케',
    alias: '니케',
    iconAsset: 'assets/game_icons/nikke.png',
    availablePeriods: [QuestPeriod.daily],
  ),
  GameCatalogEntry(
    name: '젠레스 존 제로',
    alias: '젠존제',
    iconAsset: 'assets/game_icons/zenless_zone_zero.png',
    availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
  ),
  GameCatalogEntry(
    name: '붕괴: 스타레일',
    alias: '붕스',
    iconAsset: 'assets/game_icons/honkai_star_rail.png',
    availablePeriods: [QuestPeriod.daily, QuestPeriod.weekly],
  ),
];
