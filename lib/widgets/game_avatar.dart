import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/game.dart';

class GameAvatar extends StatelessWidget {
  const GameAvatar({required this.game, this.radius = 16, super.key});

  final GameInfo game;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final catalogIcon = gameCatalog
        .where((entry) => entry.name.toLowerCase() == game.name.toLowerCase())
        .firstOrNull
        ?.iconAsset;
    final size = radius * 2;
    final borderRadius = BorderRadius.circular(radius * 0.38);

    Widget image;
    if (catalogIcon != null) {
      image = Image.asset(
        catalogIcon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallbackIcon(),
      );
    } else if (game.iconBase64 case final encoded? when encoded.isNotEmpty) {
      try {
        image = Image.memory(
          base64Decode(encoded),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _fallbackIcon(),
        );
      } catch (_) {
        image = _fallbackIcon();
      }
    } else {
      image = _fallbackIcon();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: game.color.withValues(alpha: 0.2),
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }

  Widget _fallbackIcon() =>
      Icon(Icons.videogame_asset, size: radius * 1.1, color: game.color);
}
