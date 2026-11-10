import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/game.dart';
import '../utils/game_icon.dart';

class GameSetupDraft {
  const GameSetupDraft(
    this.name,
    this.alias,
    this.enabledTypes, {
    this.iconBase64,
  });
  final String name;
  final String alias;
  final Set<GameContentType> enabledTypes;
  final String? iconBase64;
}

class GameSettingsDialog extends StatefulWidget {
  const GameSettingsDialog({
    required this.initialName,
    required this.initialTypes,
    this.initialAlias,
    this.nameReadOnly = false,
    this.allowCustomIcon = false,
    super.key,
  });

  final String initialName;
  final String? initialAlias;
  final Set<GameContentType> initialTypes;
  final bool nameReadOnly;
  final bool allowCustomIcon;

  @override
  State<GameSettingsDialog> createState() => _GameSettingsDialogState();
}

class _GameSettingsDialogState extends State<GameSettingsDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _aliasController = TextEditingController(
    text: widget.initialAlias ?? widget.initialName,
  );
  late bool _aliasManuallyEdited =
      widget.initialAlias != null && widget.initialAlias != widget.initialName;
  late final Set<GameContentType> _enabled = {...widget.initialTypes};
  String? _iconBase64;
  bool _loadingIcon = false;

  Future<void> _selectIcon() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (!mounted || file == null) return;
    setState(() => _loadingIcon = true);
    try {
      final icon = await prepareGameIcon(await file.readAsBytes());
      if (mounted) setState(() => _iconBase64 = icon);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('이미지를 불러오지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _loadingIcon = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  void _toggle(GameContentType type, bool enabled) {
    setState(() {
      if (enabled) {
        _enabled.add(type);
      } else {
        _enabled.remove(type);
      }
    });
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty || _enabled.isEmpty) return;
    final alias = _aliasController.text.trim();
    Navigator.pop(
      context,
      GameSetupDraft(name, alias.isEmpty ? name : alias, {
        ..._enabled,
      }, iconBase64: _iconBase64),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    title: const Text('게임 설정'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          readOnly: widget.nameReadOnly,
          decoration: const InputDecoration(labelText: '게임 이름'),
          onChanged: (value) => setState(() {
            if (!_aliasManuallyEdited) {
              _aliasController.value = TextEditingValue(
                text: value,
                selection: TextSelection.collapsed(offset: value.length),
              );
            }
          }),
        ),
        TextField(
          controller: _aliasController,
          decoration: const InputDecoration(
            labelText: '별칭',
            helperText: '기본값은 게임 이름은 2~3글자를 권장해요.',
          ),
          onChanged: (_) => setState(() => _aliasManuallyEdited = true),
        ),
        if (widget.allowCustomIcon) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 52,
                  height: 52,
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: _loadingIcon
                      ? const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _iconBase64 == null
                      ? const Icon(Icons.videogame_asset_outlined)
                      : Image.memory(
                          base64Decode(_iconBase64!),
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadingIcon ? null : _selectIcon,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(_iconBase64 == null ? '아이콘 사진 선택' : '사진 변경'),
                ),
              ),
              if (_iconBase64 != null)
                IconButton(
                  tooltip: '사진 삭제',
                  onPressed: () => setState(() => _iconBase64 = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Align(alignment: Alignment.centerLeft, child: Text('사용할 항목 유형')),
        ...GameContentType.values.map(
          (type) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(type.label),
            value: _enabled.contains(type),
            onChanged: (value) => _toggle(type, value ?? false),
          ),
        ),
        if (_enabled.isEmpty)
          const Text(
            '하나 이상의 유형을 선택해 주세요.',
            style: TextStyle(color: Colors.red),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: _nameController.text.trim().isEmpty || _enabled.isEmpty
            ? null
            : _submit,
        child: const Text('저장'),
      ),
    ],
  );
}
