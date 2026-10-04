import 'dart:convert';

import 'package:flutter/services.dart';

class Native {
  static const channel = MethodChannel('no.breakfast.orders/windows');
  static Future<String?> chooseFile({bool save = false}) =>
      channel.invokeMethod<String>(save ? 'saveFile' : 'openFile');
  static Future<String> encrypt(String value) async {
    final result = await channel.invokeMethod<Uint8List>(
      'protect',
      Uint8List.fromList(utf8.encode(value)),
    );
    if (result == null) {
      throw StateError('Windows secure credential storage is unavailable.');
    }
    return base64Encode(result);
  }

  static Future<String> decrypt(String value) async {
    final result = await channel.invokeMethod<Uint8List>(
      'unprotect',
      base64Decode(value),
    );
    if (result == null) {
      throw StateError('Re-enter the email password on this Windows account.');
    }
    return utf8.decode(result);
  }
}
