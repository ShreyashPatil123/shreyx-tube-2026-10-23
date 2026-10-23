/// Standardized lightweight metadata model for video items across Home, Search, History, Queue, and Playlists.
/// Contains only metadata and thumbnail URLs — NO stream URLs are resolved until playback is requested.
class TubeVideoItem {
  final String id;
  final String title;
  final String channelTitle;
  final String channelId;
  final String channelAvatarUrl;
  final String thumbnailUrl;
  final int durationSeconds;
  final int? viewCount;
  final String? viewCountText;
  final DateTime? uploadDate;
  final String? publishedTimeText;
  final bool isLive;
  final bool isShort;
  final String description;
  final bool isMembersOnly;
  final bool isPrivate;
  final String? soundTitle;

  const TubeVideoItem({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.channelId,
    this.channelAvatarUrl = '',
    this.thumbnailUrl = '',
    this.durationSeconds = 0,
    this.viewCount,
    this.viewCountText,
    this.uploadDate,
    this.publishedTimeText,
    this.isLive = false,
    this.isShort = false,
    this.description = '',
    this.isMembersOnly = false,
    this.isPrivate = false,
    this.soundTitle,
  });

  DateTime? get effectiveUploadDate => uploadDate ?? parseRelativeTime(publishedTimeText);

  TubeVideoItem copyWith({
    String? id,
    String? title,
    String? channelTitle,
    String? channelId,
    String? channelAvatarUrl,
    String? thumbnailUrl,
    int? durationSeconds,
    int? viewCount,
    String? viewCountText,
    DateTime? uploadDate,
    String? publishedTimeText,
    bool? isLive,
    bool? isShort,
    String? description,
    bool? isMembersOnly,
    bool? isPrivate,
    String? soundTitle,
  }) {
    return TubeVideoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      channelTitle: channelTitle ?? this.channelTitle,
      channelId: channelId ?? this.channelId,
      channelAvatarUrl: channelAvatarUrl ?? this.channelAvatarUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      viewCount: viewCount ?? this.viewCount,
      viewCountText: viewCountText ?? this.viewCountText,
      uploadDate: uploadDate ?? this.uploadDate,
      publishedTimeText: publishedTimeText ?? this.publishedTimeText,
      isLive: isLive ?? this.isLive,
      isShort: isShort ?? this.isShort,
      description: description ?? this.description,
      isMembersOnly: isMembersOnly ?? this.isMembersOnly,
      isPrivate: isPrivate ?? this.isPrivate,
      soundTitle: soundTitle ?? this.soundTitle,
    );
  }

  String get watchUrl => 'https://www.youtube.com/watch?v=$id';

  String get formattedDuration {
    if (isLive) return 'LIVE';
    final d = Duration(seconds: durationSeconds);
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60);
    final secs = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  String get formattedViews {
    if (viewCountText != null && viewCountText!.trim().isNotEmpty) {
      return viewCountText!.trim();
    }
    if (viewCount == null) return '';
    final count = viewCount!;
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B views';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M views';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K views';
    }
    return '$count views';
  }

  String get formattedDate {
    if (publishedTimeText != null && publishedTimeText!.trim().isNotEmpty) {
      return publishedTimeText!.trim();
    }
    final date = effectiveUploadDate;
    if (date == null) return '';
    final diff = DateTime.now().difference(date);
    if (diff.inDays >= 365) {
      final years = (diff.inDays / 365).floor();
      return '$years year${years > 1 ? "s" : ""} ago';
    } else if (diff.inDays >= 30) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months > 1 ? "s" : ""} ago';
    } else if (diff.inDays >= 7) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks > 1 ? "s" : ""} ago';
    } else if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays > 1 ? "s" : ""} ago';
    } else if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours > 1 ? "s" : ""} ago';
    } else if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} minute${diff.inMinutes > 1 ? "s" : ""} ago';
    }
    return 'Just now';
  }

  /// Parses YouTube relative date strings like "3 days ago", "Streamed 2 days ago", "1 year ago" into an approximate DateTime.
  static DateTime? parseRelativeTime(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final lower = text.toLowerCase().trim();
    final now = DateTime.now();

    if (lower.contains('just now') || lower.contains('moments ago') || lower.contains('seconds ago')) {
      return now;
    }
    if (lower.contains('yesterday')) {
      return now.subtract(const Duration(days: 1));
    }

    final match = RegExp(r'(\d+)\s*(second|minute|hour|day|week|month|year)s?\s*ago').firstMatch(lower);
    if (match != null) {
      final value = int.tryParse(match.group(1) ?? '') ?? 0;
      final unit = match.group(2) ?? '';
      switch (unit) {
        case 'second':
          return now.subtract(Duration(seconds: value));
        case 'minute':
          return now.subtract(Duration(minutes: value));
        case 'hour':
          return now.subtract(Duration(hours: value));
        case 'day':
          return now.subtract(Duration(days: value));
        case 'week':
          return now.subtract(Duration(days: value * 7));
        case 'month':
          return now.subtract(Duration(days: value * 30));
        case 'year':
          return now.subtract(Duration(days: value * 365));
      }
    }
    return null;
  }

  /// Parses view count numbers from strings like "1.4M views", "82K views", "1,240,000 views".
  static int? parseViewCount(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final clean = text.toLowerCase().replaceAll(',', '').trim();
    if (clean.contains('no views')) return 0;
    final match = RegExp(r'([\d\.]+)\s*([kmb])?').firstMatch(clean);
    if (match != null) {
      final numVal = double.tryParse(match.group(1) ?? '');
      if (numVal != null) {
        final multiplier = match.group(2);
        if (multiplier == 'k') return (numVal * 1000).toInt();
        if (multiplier == 'm') return (numVal * 1000000).toInt();
        if (multiplier == 'b') return (numVal * 1000000000).toInt();
        return numVal.toInt();
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'channelTitle': channelTitle,
        'channelId': channelId,
        'channelAvatarUrl': channelAvatarUrl,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
        'viewCount': viewCount,
        'viewCountText': viewCountText,
        'uploadDate': uploadDate?.toIso8601String(),
        'publishedTimeText': publishedTimeText,
        'isLive': isLive,
        'isShort': isShort,
        'description': description,
        'isMembersOnly': isMembersOnly,
        'isPrivate': isPrivate,
        'soundTitle': soundTitle,
      };

  factory TubeVideoItem.fromJson(Map<String, dynamic> json) => TubeVideoItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        channelTitle: json['channelTitle'] as String? ?? '',
        channelId: json['channelId'] as String? ?? '',
        channelAvatarUrl: json['channelAvatarUrl'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        viewCount: (json['viewCount'] as num?)?.toInt(),
        viewCountText: json['viewCountText'] as String?,
        uploadDate: json['uploadDate'] != null ? DateTime.tryParse(json['uploadDate'] as String) : null,
        publishedTimeText: json['publishedTimeText'] as String?,
        isLive: json['isLive'] as bool? ?? false,
        isShort: json['isShort'] as bool? ?? false,
        description: json['description'] as String? ?? '',
        isMembersOnly: json['isMembersOnly'] as bool? ?? false,
        isPrivate: json['isPrivate'] as bool? ?? false,
        soundTitle: json['soundTitle'] as String?,
      );
}

/// Explicit lifecycle states for the video playback pipeline.
enum TubePlayerStatus {
  idle,
  loadingMetadata,
  resolvingStream,
  preparingPlayer,
  buffering,
  playing,
  paused,
  completed,
  retrying,
  error,
}

/// Channel tab sorting options.
enum TubeChannelSortOrder {
  latest,
  popular,
  oldest,
}

/// Normalized items for channel sections.
class TubeChannelVideo {
  final TubeVideoItem item;
  final bool isMembersOnly;
  final bool isLive;

  const TubeChannelVideo({
    required this.item,
    this.isMembersOnly = false,
    this.isLive = false,
  });
}

class TubeChannelShort {
  final TubeVideoItem item;
  final int? viewCount;

  const TubeChannelShort({
    required this.item,
    this.viewCount,
  });
}

class TubeChannelLive {
  final TubeVideoItem item;
  final bool isCurrentlyLive;
  final String? liveViewerCountText;

  const TubeChannelLive({
    required this.item,
    required this.isCurrentlyLive,
    this.liveViewerCountText,
  });
}

class TubeChannelPlaylist {
  final String id;
  final String title;
  final String thumbnailUrl;
  final int videoCount;
  final String channelTitle;

  const TubeChannelPlaylist({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.videoCount,
    required this.channelTitle,
  });
}

class TubeChannelPost {
  final String id;
  final String authorName;
  final String authorAvatarUrl;
  final String text;
  final String publishedTimeText;
  final String? likeCountText;
  final List<String> imageUrls;

  const TubeChannelPost({
    required this.id,
    required this.authorName,
    required this.authorAvatarUrl,
    required this.text,
    required this.publishedTimeText,
    this.likeCountText,
    this.imageUrls = const [],
  });
}

/// Metadata model for a locally followed channel.
/// Terminology: "My Channels" / "Following" (NEVER "Subscribe").
class TubeChannelInfo {
  final String id;
  final String title;
  final String avatarUrl;
  final String bannerUrl;
  final String handle;
  final String subscriberCountText;
  final String description;
  final int videoCount;
  final bool isFollowed;
  final DateTime? followedAt;

  const TubeChannelInfo({
    required this.id,
    required this.title,
    required this.avatarUrl,
    this.bannerUrl = '',
    this.handle = '',
    this.subscriberCountText = '',
    this.description = '',
    this.videoCount = 0,
    this.isFollowed = false,
    this.followedAt,
  });

  TubeChannelInfo copyWith({
    bool? isFollowed,
    DateTime? followedAt,
    String? bannerUrl,
    String? handle,
    String? subscriberCountText,
    String? description,
    int? videoCount,
  }) =>
      TubeChannelInfo(
        id: id,
        title: title,
        avatarUrl: avatarUrl,
        bannerUrl: bannerUrl ?? this.bannerUrl,
        handle: handle ?? this.handle,
        subscriberCountText: subscriberCountText ?? this.subscriberCountText,
        description: description ?? this.description,
        videoCount: videoCount ?? this.videoCount,
        isFollowed: isFollowed ?? this.isFollowed,
        followedAt: followedAt ?? this.followedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'avatarUrl': avatarUrl,
        'bannerUrl': bannerUrl,
        'handle': handle,
        'subscriberCountText': subscriberCountText,
        'description': description,
        'videoCount': videoCount,
        'isFollowed': isFollowed,
        'followedAt': followedAt?.toIso8601String(),
      };

  factory TubeChannelInfo.fromJson(Map<String, dynamic> json) => TubeChannelInfo(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String? ?? '',
        bannerUrl: json['bannerUrl'] as String? ?? '',
        handle: json['handle'] as String? ?? '',
        subscriberCountText: json['subscriberCountText'] as String? ?? '',
        description: json['description'] as String? ?? '',
        videoCount: (json['videoCount'] as num?)?.toInt() ?? 0,
        isFollowed: json['isFollowed'] as bool? ?? false,
        followedAt: json['followedAt'] != null ? DateTime.tryParse(json['followedAt'] as String) : null,
      );
}

/// Model for a locally created user playlist.
class TubeLocalPlaylist {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final List<TubeVideoItem> videos;

  const TubeLocalPlaylist({
    required this.id,
    required this.title,
    this.description = '',
    required this.createdAt,
    required this.videos,
  });

  String get thumbnailUrl => videos.isNotEmpty ? videos.first.thumbnailUrl : '';
  int get count => videos.length;

  TubeLocalPlaylist copyWith({
    String? title,
    String? description,
    List<TubeVideoItem>? videos,
  }) =>
      TubeLocalPlaylist(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        createdAt: createdAt,
        videos: videos ?? this.videos,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'createdAt': createdAt.toIso8601String(),
        'videos': videos.map((v) => v.toJson()).toList(),
      };

  factory TubeLocalPlaylist.fromJson(Map<String, dynamic> json) => TubeLocalPlaylist(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        videos: (json['videos'] as List<dynamic>?)
                ?.map((e) => TubeVideoItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Watch history item with resume timestamp and completion percentage.
class TubeHistoryItem {
  final TubeVideoItem video;
  final DateTime watchedAt;
  final int positionMs;
  final int durationMs;

  const TubeHistoryItem({
    required this.video,
    required this.watchedAt,
    required this.positionMs,
    required this.durationMs,
  });

  double get completionRatio {
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  double get progressRatio => completionRatio;

  bool get isResumeAvailable => positionMs > 5000 && completionRatio < 0.95;

  String get formattedResumePosition {
    final d = Duration(milliseconds: positionMs);
    final mins = d.inMinutes.remainder(60);
    final secs = d.inSeconds.remainder(60);
    if (d.inHours > 0) {
      return '${d.inHours}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'video': video.toJson(),
        'watchedAt': watchedAt.toIso8601String(),
        'positionMs': positionMs,
        'durationMs': durationMs,
      };

  factory TubeHistoryItem.fromJson(Map<String, dynamic> json) => TubeHistoryItem(
        video: TubeVideoItem.fromJson(json['video'] as Map<String, dynamic>),
        watchedAt: DateTime.tryParse(json['watchedAt'] as String? ?? '') ?? DateTime.now(),
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      );
}

/// Behavioral interaction signal used strictly on-device for recommendation scoring.
class TubeWatchSignal {
  final String videoId;
  final String title;
  final String channelId;
  final String channelTitle;
  final double completionRatio;
  final int watchDurationSeconds;
  final bool isRewatch;
  final bool isFastSkip; // watched < 15% within 30 seconds
  final DateTime timestamp;

  const TubeWatchSignal({
    required this.videoId,
    this.title = '',
    this.channelId = '',
    required this.channelTitle,
    required this.completionRatio,
    required this.watchDurationSeconds,
    this.isRewatch = false,
    this.isFastSkip = false,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'channelId': channelId,
        'channelTitle': channelTitle,
        'completionRatio': completionRatio,
        'watchDurationSeconds': watchDurationSeconds,
        'isRewatch': isRewatch,
        'isFastSkip': isFastSkip,
        'timestamp': timestamp.toIso8601String(),
      };

  factory TubeWatchSignal.fromJson(Map<String, dynamic> json) => TubeWatchSignal(
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        channelId: json['channelId'] as String? ?? '',
        channelTitle: json['channelTitle'] as String? ?? '',
        completionRatio: (json['completionRatio'] as num?)?.toDouble() ?? 0.0,
        watchDurationSeconds: (json['watchDurationSeconds'] as num?)?.toInt() ?? 0,
        isRewatch: json['isRewatch'] as bool? ?? false,
        isFastSkip: json['isFastSkip'] as bool? ?? false,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Read-only public comments model.
class TubeCommentItem {
  final String id;
  final String author;
  final String authorAvatar;
  final String text;
  final String publishedTime;
  final int likeCount;

  const TubeCommentItem({
    required this.id,
    required this.author,
    required this.authorAvatar,
    required this.text,
    required this.publishedTime,
    required this.likeCount,
  });
}
