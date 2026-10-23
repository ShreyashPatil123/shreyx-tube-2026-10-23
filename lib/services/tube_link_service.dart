import 'package:flutter/services.dart';

class TubeLinkService {
  static final Map<String, String> _originals = {};
  static String? originalFor(String id) => _originals[id];
  static void remember(String id, String url) {
    _originals.remove(id);
    _originals[id] = url;
    if (_originals.length > 16) _originals.remove(_originals.keys.first);
  }

  static void clear() => _originals.clear();
  static const channel = MethodChannel('com.shreyx.tube/links');
  static Future<bool> openSettings() async {
    try {
      return await channel.invokeMethod<bool>('openLinkSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> pending() async {
    try {
      final value = await channel.invokeMethod('pending');
      return value is List
          ? value
              .whereType<Map>()
              .map((v) => Map<String, dynamic>.from(v))
              .toList()
          : [];
    } on MissingPluginException {
      return [];
    }
  }

  static Future<void> acknowledge(String id) async =>
      channel.invokeMethod('ack', {'id': id});
  static Future<bool> openYouTube(String url) async {
    try {
      return await channel.invokeMethod<bool>('openYouTube', {'url': url}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
