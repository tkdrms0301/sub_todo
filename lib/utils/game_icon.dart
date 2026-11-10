import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

Uint8List _makeSquareIcon(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('이미지 파일을 읽을 수 없습니다.');
  final side = math.min(decoded.width, decoded.height);
  final cropped = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  return Uint8List.fromList(
    img.encodePng(img.copyResize(cropped, width: 128, height: 128)),
  );
}

Future<String> prepareGameIcon(Uint8List bytes) async =>
    base64Encode(await compute(_makeSquareIcon, bytes));

Future<String> loadGameIconAsset(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final bytes = Uint8List.view(
    data.buffer,
    data.offsetInBytes,
    data.lengthInBytes,
  );
  return prepareGameIcon(bytes);
}
