import 'package:flutter/material.dart';
import 'screens/calendar_screen.dart';

class QuestCalendarApp extends StatelessWidget {
  const QuestCalendarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'To Do 캘린더',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5264C8)),
          scaffoldBackgroundColor: const Color(0xFFF6F7FB),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        home: const CalendarScreen(),
      );
}
