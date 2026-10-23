enum TubeDownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

class TubeDownloadItem {
  final String videoId;
  final String title;
  final String channelTitle;
  final String channelId;
  final String thumbnailUrl;
  final String quality;
  final String videoPath;
  final String? audioPath;
  final bool isAdaptive;
  final int durationSeconds;
  TubeDownloadStatus status;
  double progress;
  int totalBytes;
  int downloadedBytes;
  final DateTime downloadedAt;

  TubeDownloadItem({
    required this.videoId,
    required this.title,
    required this.channelTitle,
    required this.channelId,
    required this.thumbnailUrl,
    required this.quality,
    required this.videoPath,
    this.audioPath,
    this.isAdaptive = false,
    this.durationSeconds = 0,
    this.status = TubeDownloadStatus.queued,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    DateTime? downloadedAt,
  }) : downloadedAt = downloadedAt ?? DateTime.now();

  String get formattedSize {
    if (totalBytes <= 0) return '';
    final mb = totalBytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(1)} GB';
    }
    return '${mb.toStringAsFixed(1)} MB';
  }

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channelTitle': channelTitle,
        'channelId': channelId,
        'thumbnailUrl': thumbnailUrl,
        'quality': quality,
        'videoPath': videoPath,
        'audioPath': audioPath,
        'isAdaptive': isAdaptive,
        'durationSeconds': durationSeconds,
        'status': status.name,
        'progress': progress,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'downloadedAt': downloadedAt.toIso8601String(),
      };

  factory TubeDownloadItem.fromJson(Map<String, dynamic> json) => TubeDownloadItem(
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        channelTitle: json['channelTitle'] as String? ?? '',
        channelId: json['channelId'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        quality: json['quality'] as String? ?? '720p',
        videoPath: json['videoPath'] as String? ?? '',
        audioPath: json['audioPath'] as String?,
        isAdaptive: json['isAdaptive'] as bool? ?? false,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        status: TubeDownloadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => TubeDownloadStatus.completed,
        ),
        progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
        totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
        downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
        downloadedAt: DateTime.tryParse(json['downloadedAt'] as String? ?? '') ?? DateTime.now(),
      );
}
