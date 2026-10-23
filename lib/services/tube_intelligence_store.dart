import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import 'tube_database_service.dart';
import 'tube_storage_service.dart';

class TubeIntelligenceStore extends ChangeNotifier {
  TubeIntelligenceStore._();
  static final _instance = TubeIntelligenceStore._();
  factory TubeIntelligenceStore() => _instance;
  @visibleForTesting
  TubeIntelligenceStore.withDatabase(this._testDatabase);
  Database? _testDatabase;
  Future<Database> get _db async =>
      _testDatabase ?? await TubeDatabaseService().database;
  static const _secure = FlutterSecureStorage();
  static const tokenKey = 'tube_ai_gateway_access_v1';
  int revision = 0;
  bool externalAllowed = false;
  String endpoint = '';
  String _token = '';
  String get accessToken => _token;
  Future<void> init() async {
    final expected = revision;
    final db = await _db;
    final rows = await db.query(
      'settings',
      where: 'key IN (?, ?)',
      whereArgs: ['ai_external_allowed', 'ai_gateway_url'],
    );
    final values = {for (final row in rows) row['key']: row['value']};
    var token = '';
    var allowed = values['ai_external_allowed'] == 'true';
    try {
      token = await _secure.read(key: tokenKey) ?? '';
    } catch (_) {
      allowed = false;
    }
    if (revision != expected || _resetting) return;
    externalAllowed = allowed;
    endpoint = values['ai_gateway_url']?.toString() ?? '';
    _token = token;
  }

  static Uri validateEndpoint(String raw, {bool allowLoopback = kDebugMode}) {
    final uri = Uri.tryParse(raw.trim());
    final local = uri?.host == '127.0.0.1' ||
        uri?.host == 'localhost' ||
        uri?.host == '::1';
    final host = uri?.host.toLowerCase() ?? '';
    final ipv4 = RegExp(r'^\d+(\.\d+){3}$').hasMatch(host);
    if (uri == null ||
        host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path) ||
        (!(allowLoopback && local && uri.scheme == 'http') &&
            (uri.scheme != 'https' ||
                local ||
                ipv4 ||
                host.contains(':') ||
                !host.contains('.') ||
                host.endsWith('.local') ||
                host.endsWith('.internal') ||
                (uri.hasPort && uri.port != 443)))) {
      throw const FormatException(
        'Use the public HTTPS origin of your AI gateway, without a path, query or credentials.',
      );
    }
    return uri.replace(path: '');
  }

  Future<void> _configWrites = Future<void>.value();
  bool _resetting = false;
  int _resetEpoch = 0;
  Future<void> configure({
    required bool allowed,
    required String url,
    required String token,
  }) {
    if (_resetting) {
      return Future.error(StateError('Privacy reset is in progress.'));
    }
    final expected = _resetEpoch;
    final next = _configWrites.then(
      (_) => _configure(
        allowed: allowed,
        url: url,
        token: token,
        expected: expected,
      ),
    );
    _configWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _configure({
    required bool allowed,
    required String url,
    required String token,
    required int expected,
  }) async {
    final clean = url.trim();
    if (clean.isNotEmpty) validateEndpoint(clean);
    if (allowed &&
        (clean.isEmpty || token.trim().length < 24 || token.length > 512)) {
      throw const FormatException(
        'External AI needs an HTTPS gateway and your gateway access token (24–512 characters). Never enter a Gemini API key here.',
      );
    }
    if (token.trim().startsWith('AIza')) {
      throw const FormatException(
        'Provider API keys belong on the server, never in this app.',
      );
    }
    if (expected != _resetEpoch || _resetting) {
      throw StateError('Privacy settings changed. Retry configuration.');
    }
    await _secure.write(key: tokenKey, value: token.trim());
    final db = await _db;
    await db.transaction((tx) async {
      for (final entry in {
        'ai_external_allowed': '$allowed',
        'ai_gateway_url': clean,
      }.entries) {
        await tx.insert(
            'settings',
            {
              'key': entry.key,
              'value': entry.value,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    if (expected != _resetEpoch || _resetting) {
      throw StateError('Privacy settings changed. Retry configuration.');
    }
    externalAllowed = allowed;
    endpoint = clean;
    _token = token.trim();
    revision++;
    notifyListeners();
  }

  Future<List<Map<String, Object?>>> listSaved() async {
    if (TubeStorageService().isIncognito) return [];
    final rows = await (await _db).query(
      'video_intelligence',
      orderBy: 'updated_at DESC',
      limit: 50,
    );
    return TubeStorageService().isIncognito ? [] : rows;
  }

  Future<Map<String, Object?>?> load(String videoId) async {
    if (TubeStorageService().isIncognito) return null;
    final rows = await (await _db).query(
      'video_intelligence',
      where: 'video_id = ?',
      whereArgs: [videoId],
      limit: 1,
    );
    return rows.isEmpty || TubeStorageService().isIncognito ? null : rows.first;
  }

  Future<void> save({
    required String videoId,
    required String title,
    required String notes,
    required String responses,
    required String digest,
    required int expectedRevision,
  }) async {
    if (TubeStorageService().isIncognito) {
      throw StateError('Saving is disabled in Incognito.');
    }
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) &&
        videoId != 'demo-study') {
      throw const FormatException('Invalid video.');
    }
    if (notes.length > 30000 ||
        responses.length > 60000 ||
        title.length > 300) {
      throw const FormatException('Study material is too large to save.');
    }
    final db = await _db;
    await db.transaction((tx) async {
      if (expectedRevision != revision || TubeStorageService().isIncognito) {
        throw StateError('Privacy settings changed. Retry saving.');
      }
      await tx.insert(
          'video_intelligence',
          {
            'video_id': videoId,
            'title': title,
            'notes': notes,
            'responses': responses,
            'digest': digest,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      await tx.rawDelete(
        'DELETE FROM video_intelligence WHERE video_id NOT IN (SELECT video_id FROM video_intelligence ORDER BY updated_at DESC LIMIT 50)',
      );
    });
  }

  Future<void> clearMaterials() async {
    revision++;
    notifyListeners();
    await (await _db).delete('video_intelligence');
    // The first notification cancels work immediately. Refresh libraries again
    // after the transaction so a query started by that notification cannot
    // leave pre-deletion rows visible in another open workbench.
    revision++;
    notifyListeners();
  }

  Future<void> reset() async {
    _resetting = true;
    _resetEpoch++;
    externalAllowed = false;
    endpoint = '';
    _token = '';
    revision++;
    notifyListeners();
    try {
      await _configWrites;
      await _secure.delete(key: tokenKey);
      await (await _db).delete(
        'settings',
        where: 'key IN (?, ?)',
        whereArgs: ['ai_external_allowed', 'ai_gateway_url'],
      );
    } finally {
      _resetting = false;
    }
  }
}
