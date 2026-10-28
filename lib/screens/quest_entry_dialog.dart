import 'package:flutter/material.dart';

import '../models/game.dart';
import '../models/quest.dart';

class QuestDraft {
  const QuestDraft(
    this.gameId,
    this.title,
    this.period, {
    this.startDate,
    this.endDate,
  });

  final String gameId;
  final String title;
  final QuestPeriod period;
  final DateTime? startDate;
  final DateTime? endDate;
}

class QuestEntryDialog extends StatefulWidget {
  const QuestEntryDialog({
    required this.games,
    this.initialQuest,
    this.initialGameId,
    super.key,
  });
  final List<GameInfo> games;
  final GameQuest? initialQuest;
  final String? initialGameId;

  @override
  State<QuestEntryDialog> createState() => _QuestEntryDialogState();
}

class _QuestEntryDialogState extends State<QuestEntryDialog> {
  final _controller = TextEditingController();
  late String _gameId;
  late QuestPeriod _period;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

  @override
  void initState() {
    super.initState();
    final quest = widget.initialQuest;
    _gameId = widget.initialGameId ?? widget.games.first.id;
    _period = quest?.period ?? widget.games.first.availablePeriods.first;
    _rangeStart = quest?.startDate ?? _monday(DateTime.now());
    _rangeEnd = quest?.endDate ?? _rangeStart.add(const Duration(days: 6));
    _controller.text = quest?.title ?? '';
  }

  GameInfo get _selectedGame =>
      widget.games.firstWhere((game) => game.id == _gameId);

  DateTime _monday(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  String _dateLabel(DateTime date) =>
      date.year.toString() +
      '/' +
      date.month.toString().padLeft(2, '0') +
      '/' +
      date.day.toString().padLeft(2, '0');

  Future<void> _chooseRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      helpText: '주간 퀘스트 기간 선택',
    );
    if (range == null) return;
    final start = DateTime(
      range.start.year,
      range.start.month,
      range.start.day,
    );
    final end = DateTime(range.end.year, range.end.month, range.end.day);
    if (end.difference(start).inDays >= 7) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('반복 주간의 체크 기간은 최대 7일로 선택해 주세요.')),
      );
      return;
    }
    setState(() {
      _rangeStart = start;
      _rangeEnd = end;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _controller.text.trim();
    final periodAllowed =
        _selectedGame.availablePeriods.contains(_period) ||
        (_period == widget.initialQuest?.period);
    if (title.isNotEmpty && periodAllowed) {
      Navigator.pop(
        context,
        QuestDraft(
          _gameId,
          title,
          _period,
          startDate: _period == QuestPeriod.weekly ? _rangeStart : null,
          endDate: _period == QuestPeriod.weekly ? _rangeEnd : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final periods = <QuestPeriod>{
      ..._selectedGame.availablePeriods,
      if (widget.initialQuest != null) widget.initialQuest!.period,
    }.toList();
    return AlertDialog(
      title: Text(widget.initialQuest == null ? '퀘스트 추가' : '퀘스트 수정'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _gameId,
              decoration: const InputDecoration(labelText: '게임'),
              items: widget.games
                  .map(
                    (g) => DropdownMenuItem(value: g.id, child: Text(g.name)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _gameId = value;
                  if (!_selectedGame.availablePeriods.contains(_period)) {
                    _period = _selectedGame.availablePeriods.first;
                  }
                });
              },
            ),
            const SizedBox(height: 14),
            SegmentedButton<QuestPeriod>(
              segments: periods
                  .map(
                    (period) => ButtonSegment(
                      value: period,
                      label: Text(period.label + ' 퀘스트'),
                    ),
                  )
                  .toList(),
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _period = selection.first),
            ),
            if (_period == QuestPeriod.weekly) ...[
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range),
                title: const Text('체크 기간'),
                subtitle: Text(
                  _dateLabel(_rangeStart) + ' ~ ' + _dateLabel(_rangeEnd),
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _chooseRange,
              ),
              const Text(
                '선택한 기간이 7일마다 반복됩니다. 같은 기간에 있는 날짜끼리 완료 상태를 공유합니다.',
                style: TextStyle(fontSize: 12),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '퀘스트 이름'),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.initialQuest == null ? '추가' : '수정 완료'),
        ),
      ],
    );
  }
}
