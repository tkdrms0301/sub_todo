import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/app_data_backup.dart';
import 'screens/calendar_screen.dart';
import 'screens/first_run_setup_screen.dart';

class QuestCalendarApp extends StatelessWidget {
  const QuestCalendarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '할 건 해야지',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5264C8)),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    home: const _AppStartupGate(),
  );
}

class _AppStartupGate extends StatefulWidget {
  const _AppStartupGate();

  @override
  State<_AppStartupGate> createState() => _AppStartupGateState();
}

class _AppStartupGateState extends State<_AppStartupGate> {
  static const _setupCompletedKey = 'sub_todo_initial_setup_completed_v1';
  static const _localDataKey = 'sub_todo_app_data_v1';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  bool? _setupCompleted;
  AppDataBackup? _existingData;

  @override
  void initState() {
    super.initState();
    _checkStartupState();
  }

  Future<void> _checkStartupState() async {
    var completed = false;
    try {
      completed = await _preferences.getBool(_setupCompletedKey) ?? false;
      if (!completed) {
        final saved = await _preferences.getString(_localDataKey);
        if (saved != null) {
          try {
            _existingData = AppDataBackup.decode(saved);
          } catch (_) {
            // Let the user recover from a backup or start fresh if local data
            // from an older or damaged format cannot be read.
          }
        }
      }
    } catch (_) {
      completed = false;
    }
    if (mounted) setState(() => _setupCompleted = completed);
  }

  @override
  Widget build(BuildContext context) {
    final setupCompleted = _setupCompleted;
    if (setupCompleted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (setupCompleted) return const CalendarScreen();
    return FirstRunSetupScreen(
      existingData: _existingData,
      onComplete: () => setState(() => _setupCompleted = true),
    );
  }
}
