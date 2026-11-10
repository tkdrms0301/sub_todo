import 'dart:convert';

import 'calendar_event.dart';
import 'game.dart';

class AppDataBackup {
  const AppDataBackup({required this.games, required this.events});

  static const formatName = 'sub_todo_backup';
  static const currentVersion = 1;

  final List<GameInfo> games;
  final List<CalendarEvent> events;

  Map<String, dynamic> toJson() => {
    'format': formatName,
    'version': currentVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'games': games.map((game) => game.toJson()).toList(),
    'events': events.map((event) => event.toJson()).toList(),
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory AppDataBackup.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('백업 파일 최상위 값은 객체여야 합니다.');
    }
    final json = Map<String, dynamic>.from(value);
    if (json['format'] != formatName) {
      throw const FormatException('할 건 해야지 앱의 백업 파일이 아닙니다.');
    }
    if (json['version'] != currentVersion) {
      throw FormatException('지원하지 않는 백업 버전입니다: ${json['version']}');
    }
    final rawGames = json['games'];
    final rawEvents = json['events'];
    if (rawGames is! List || rawGames.any((item) => item is! Map)) {
      throw const FormatException('백업의 게임 목록이 올바르지 않습니다.');
    }
    if (rawEvents is! List || rawEvents.any((item) => item is! Map)) {
      throw const FormatException('백업의 일정 목록이 올바르지 않습니다.');
    }
    return AppDataBackup(
      games: rawGames
          .map(
            (item) => GameInfo.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      events: rawEvents
          .map(
            (item) =>
                CalendarEvent.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
    );
  }

  factory AppDataBackup.decode(String contents) =>
      AppDataBackup.fromJson(jsonDecode(contents));
}
