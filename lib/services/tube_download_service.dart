import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/tube_download_models.dart';
import '../models/tube_models.dart';
import '../models/tube_stream.dart';
import 'tube_storage_service.dart';

/// Complete Offline Download Service.
/// Stores media in app-private storage for privacy and automatic cleanup.
/// Handles both single progressive streams and separate adaptive video+audio streams,
/// maintaining local multi-track representation for zero-network playback.
class TubeDownloadService {
  static final TubeDownloadService _instance = TubeDownloadService._internal();
  factory TubeDownloadService() => _instance;
  TubeDownloadService._internal();

  final TubeStorageService _storageService = TubeStorageService();
  final List<TubeDownloadItem> _downloads = [];
  final Map<String, HttpClientRequest> _activeRequests = {};
  bool _isInitialized = false;
  bool _resetting = false;
  final Set<Future<void>> _tasks = {};
  final Set<HttpClient> _clients = {};

  Future<void> clearAllDownloads() async {
    _resetting = true;
    try {
      for (final client in _clients.toList()) {
        client.close(force: true);
      }
      for (final request in _activeRequests.values.toList()) {
        request.abort();
      }
      await Future.wait(_tasks.toList());
      final docs = await getApplicationDocumentsDirectory();
      // Never follow stored/user-controlled paths. Delete only this app-owned directory.
      final directory = Directory('${docs.path}/shreyx_downloads');
      if (await FileSystemEntity.type(directory.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw StateError('Download directory must not be a symbolic link');
      }
      if (await directory.exists()) await directory.delete(recursive: true);
      _downloads.clear();
      _activeRequests.clear();
      await _saveDownloads();
    } finally {
      _resetting = false;
    }
  }

  final StreamController<List<TubeDownloadItem>> _downloadController =
      StreamController<List<TubeDownloadItem>>.broadcast();
  Stream<List<TubeDownloadItem>> get downloadsStream =>
      _downloadController.stream;

  List<TubeDownloadItem> get downloads => List.unmodifiable(_downloads);
  int get completedCount =>
      _downloads.where((d) => d.status == TubeDownloadStatus.completed).length;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final jsonStr = await _storageService.readStoreFile('downloads.json');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        _downloads.clear();
        for (final item in list) {
          final downloadItem =
              TubeDownloadItem.fromJson(item as Map<String, dynamic>);
          // Verify physical file exists on disk
          if (File(downloadItem.videoPath).existsSync()) {
            _downloads.add(downloadItem);
          }
        }
      }
      _isInitialized = true;
      _downloadController.add(List.unmodifiable(_downloads));
    } catch (e) {
      debugPrint('[TubeDownloadService] Init error: $e');
      rethrow;
    }
  }

  bool isDownloaded(String videoId) {
    return _downloads.any((d) =>
        d.videoId == videoId && d.status == TubeDownloadStatus.completed);
  }

  TubeDownloadItem? getDownload(String videoId) {
    try {
      return _downloads.firstWhere((d) => d.videoId == videoId);
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getDownloadsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/shreyx_downloads');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _saveDownloads() async {
    final list = _downloads.map((d) => d.toJson()).toList();
    await _storageService.writeStoreFile('downloads.json', jsonEncode(list));
    _downloadController.add(List.unmodifiable(_downloads));
  }

  Future<void> startDownload({
    required TubeVideoItem video,
    required TubeVideoStream stream,
  }) async {
    if (_resetting) throw StateError('Local data is being cleared');
    await init();

    // Check if already downloading or downloaded
    if (_downloads.any((d) =>
        d.videoId == video.id && d.status == TubeDownloadStatus.downloading)) {
      debugPrint(
          '[TubeDownloadService] Download already in progress for ${video.id}');
      return;
    }

    final dir = await _getDownloadsDir();
    final cleanQuality = stream.resolution.replaceAll('p', '');
    final isAdaptive =
        stream.pairedAudioUrl != null && stream.pairedAudioUrl!.isNotEmpty;

    final videoFilePath = '${dir.path}/${video.id}_${cleanQuality}p.mp4';
    final audioFilePath =
        isAdaptive ? '${dir.path}/${video.id}_audio.m4a' : null;

    final downloadItem = TubeDownloadItem(
      videoId: video.id,
      title: video.title,
      channelTitle: video.channelTitle,
      channelId: video.channelId,
      thumbnailUrl: video.thumbnailUrl,
      quality: stream.resolution,
      videoPath: videoFilePath,
      audioPath: audioFilePath,
      isAdaptive: isAdaptive,
      durationSeconds: video.durationSeconds,
      status: TubeDownloadStatus.downloading,
      progress: 0.0,
    );

    _downloads.removeWhere((d) => d.videoId == video.id);
    _downloads.insert(0, downloadItem);
    await _saveDownloads();

    // Launch background download task
    final task = _executeDownload(downloadItem, stream);
    _tasks.add(task);
    unawaited(task.whenComplete(() => _tasks.remove(task)));
  }

  Future<void> _executeDownload(
      TubeDownloadItem item, TubeVideoStream stream) async {
    final client = HttpClient();
    _clients.add(client);
    client.connectionTimeout = const Duration(seconds: 15);

    try {
      if (!item.isAdaptive) {
        // Single progressive media download
        await _downloadFile(client, stream.url, File(item.videoPath),
            (received, total) {
          item.downloadedBytes = received;
          item.totalBytes = total;
          item.progress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;
          _downloadController.add(List.unmodifiable(_downloads));
        }, videoId: item.videoId);
      } else {
        // Multi-track adaptive download: video stream + audio stream
        int videoTotal = 0;
        int videoReceived = 0;
        int audioTotal = 0;
        int audioReceived = 0;

        // 1. Download video track
        await _downloadFile(client, stream.url, File(item.videoPath),
            (received, total) {
          videoReceived = received;
          videoTotal = total;
          final currentTotal = videoTotal + audioTotal;
          final currentRec = videoReceived + audioReceived;
          item.downloadedBytes = currentRec;
          item.totalBytes = currentTotal;
          item.progress = currentTotal > 0
              ? (currentRec / currentTotal).clamp(0.0, 0.85)
              : 0.0;
          _downloadController.add(List.unmodifiable(_downloads));
        }, videoId: item.videoId);

        // 2. Download audio track
        if (item.audioPath != null && stream.pairedAudioUrl != null) {
          await _downloadFile(
              client, stream.pairedAudioUrl!, File(item.audioPath!),
              (received, total) {
            audioReceived = received;
            audioTotal = total;
            final currentTotal = videoTotal + audioTotal;
            final currentRec = videoReceived + audioReceived;
            item.downloadedBytes = currentRec;
            item.totalBytes = currentTotal;
            item.progress = currentTotal > 0
                ? (currentRec / currentTotal).clamp(0.0, 1.0)
                : 0.85;
            _downloadController.add(List.unmodifiable(_downloads));
          }, videoId: item.videoId);
        }
      }

      item.status = TubeDownloadStatus.completed;
      item.progress = 1.0;
      await _saveDownloads();
      debugPrint('[TubeDownloadService] Download completed: ${item.title}');
    } catch (e) {
      debugPrint('[TubeDownloadService] Download error: $e');
      item.status = TubeDownloadStatus.failed;
      await _saveDownloads();
    } finally {
      client.close();
      _clients.remove(client);
      _activeRequests.remove(item.videoId);
    }
  }

  Future<void> _downloadFile(
    HttpClient client,
    String url,
    File destination,
    void Function(int received, int total) onProgress, {
    String? videoId,
  }) async {
    final uri = Uri.parse(url);
    final request = await client.getUrl(uri);
    if (videoId != null) {
      _activeRequests[videoId] = request;
    }

    final response = await request.close();
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('HTTP ${response.statusCode} while downloading');
    }

    final total = response.contentLength;
    int received = 0;

    final sink = destination.openWrite();
    try {
      await response.listen((chunk) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, total);
      }).asFuture<void>();
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  void cancelDownload(String videoId) {
    final req = _activeRequests.remove(videoId);
    req?.abort();
    final item = getDownload(videoId);
    if (item != null && item.status == TubeDownloadStatus.downloading) {
      item.status = TubeDownloadStatus.canceled;
      _saveDownloads();
    }
  }

  Future<void> deleteDownload(String videoId) async {
    cancelDownload(videoId);
    final item = getDownload(videoId);
    if (item != null) {
      try {
        final vFile = File(item.videoPath);
        if (vFile.existsSync()) vFile.deleteSync();
        if (item.audioPath != null) {
          final aFile = File(item.audioPath!);
          if (aFile.existsSync()) aFile.deleteSync();
        }
      } catch (e) {
        debugPrint('[TubeDownloadService] Error deleting files: $e');
      }

      _downloads.removeWhere((d) => d.videoId == videoId);
      await _saveDownloads();
    }
  }

  /// Constructs an offline playable stream representation
  TubeVideoStream getOfflineStream(TubeDownloadItem item) {
    return TubeVideoStream(
      url: File(item.videoPath).uri.toString(),
      pairedAudioUrl:
          item.audioPath != null ? File(item.audioPath!).uri.toString() : null,
      resolution: item.quality,
      width: 1280,
      height: 720,
      container: 'mp4',
      mimeType: 'video/mp4',
      codec: 'avc1',
      fps: 30,
      bitrate: 2500000,
      isVideoOnly: item.isAdaptive,
      deliveryMethod: 'PROGRESSIVE',
      manifestType: 'PROGRESSIVE',
    );
  }
}
