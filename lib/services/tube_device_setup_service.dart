import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'tube_database_service.dart';

class TubeDeviceSetupStatus {
  const TubeDeviceSetupStatus(this.values);
  final Map<String, dynamic> values;
  bool get available => values['available'] == true;
  bool get notificationsEnabled => values['notificationsEnabled'] == true;
  bool get canRequestNotifications => values['canRequestNotifications'] == true;
  bool get linksSupported => values['linksSupported'] == true;
  bool get linksAllowed => values['linksAllowed'] == true;
  Map<String, dynamic> get domains =>
      Map<String, dynamic>.from(values['domains'] as Map? ?? {});
  int get selectedDomains =>
      domains.values.where((v) => v == 'selected' || v == 'verified').length;
  bool get linksReady =>
      linksAllowed && domains.isNotEmpty && selectedDomains == domains.length;
  bool get youtubeInstalled => values['youtubeInstalled'] == true;
  bool get youtubeMusicInstalled => values['youtubeMusicInstalled'] == true;
  bool get pipSupported => values['pipSupported'] == true;
  bool get pipEnabled => values['pipEnabled'] == true;
}

class TubeDeviceSetupService extends ChangeNotifier {
  TubeDeviceSetupService._()
      : _read = TubeDatabaseService().getSetting,
        _write = TubeDatabaseService().setSetting;
  static final _instance = TubeDeviceSetupService._();
  factory TubeDeviceSetupService() => _instance;
  @visibleForTesting
  TubeDeviceSetupService.withStore(this._read, this._write);
  final Future<String?> Function(String) _read;
  final Future<void> Function(String, String) _write;
  static const channel = MethodChannel('com.shreyx.tube/device_setup');
  static const setting = 'device_setup_v1';
  bool _pending = false;
  bool get pending =>
      _pending && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<void> init({TargetPlatform? platform}) async {
    _pending = (platform ?? defaultTargetPlatform) == TargetPlatform.android &&
        !kIsWeb &&
        await _read(setting) != 'done';
    notifyListeners();
  }

  Future<void> complete() async {
    await _write(setting, 'done');
    _pending = false;
    notifyListeners();
  }

  void reset() {
    _pending = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    notifyListeners();
  }

  static Future<TubeDeviceSetupStatus> inspect() async {
    try {
      final data = await channel.invokeMapMethod<String, dynamic>('status');
      return TubeDeviceSetupStatus(data ?? {});
    } on PlatformException {
      return const TubeDeviceSetupStatus({});
    } on MissingPluginException {
      return const TubeDeviceSetupStatus({});
    }
  }

  static Future<bool> action(String action) async {
    try {
      return await channel.invokeMethod<bool>(action) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
