package com.shreyx.tube

import android.util.Log
import org.schabi.newpipe.extractor.NewPipe
import org.schabi.newpipe.extractor.ServiceList
import org.schabi.newpipe.extractor.localization.ContentCountry
import org.schabi.newpipe.extractor.localization.Localization
import org.schabi.newpipe.extractor.stream.AudioStream
import org.schabi.newpipe.extractor.stream.StreamInfo
import org.schabi.newpipe.extractor.stream.SubtitlesStream
import org.schabi.newpipe.extractor.stream.VideoStream

/**
 * Native YouTube extraction engine backed by NewPipeExtractor.
 * Extracts format-rich stream descriptions for container-aware Media3 routing.
 */
object TubeExtractor {
    private const val TAG = "TubeExtractor"

    private val initLock = Any()
    @Volatile
    private var initialized = false

    fun ensureInitialized() {
        if (initialized) return
        synchronized(initLock) {
            if (initialized) return
            NewPipe.init(
                NoteNativeDownloader(),
                Localization("en", "US"),
                ContentCountry("US")
            )
            initialized = true
            Log.i(TAG, "NewPipeExtractor initialized successfully")
        }
    }

    internal fun failureReason(error: Throwable): String {
        var cause: Throwable? = error
        repeat(8) {
            val current = cause ?: return@repeat
            val text = current.message?.lowercase() ?: ""
            val type = current.javaClass.simpleName
            if ((type.contains("Content") || type.contains("Unplayable")) &&
                (text.contains("members-only") || text.contains("members only") || text.contains("only available to members"))) return "members_only"
            if (current is java.io.IOException) return "network_failed"
            cause = current.cause
        }
        return "extraction_failed"
    }

    fun extract(videoId: String): Map<String, Any?> {
        if (videoId.isBlank()) {
            return mapOf(
                "ok" to false,
                "reason" to "invalid_id",
                "message" to "No video ID provided"
            )
        }

        return try {
            ensureInitialized()
            val watchUrl = "https://www.youtube.com/watch?v=$videoId"
            Log.i(TAG, "Extracting metadata and streams for $videoId...")
            val info = StreamInfo.getInfo(ServiceList.YouTube, watchUrl)

            // 1. Progressive Streams (Video + Audio combined, e.g. 360p / 720p)
            val progressiveList = mutableListOf<Map<String, Any?>>()
            info.videoStreams?.filter { it.isUrl && !it.content.isNullOrBlank() }?.forEach { vs ->
                val container = vs.format?.suffix ?: "mp4"
                val mimeType = vs.format?.mimeType ?: "video/mp4"
                val codec = vs.codec ?: ""
                val res = vs.resolution ?: "${vs.height}p"
                val bitrate = vs.bitrate

                Log.d(TAG, "[STREAM-INSPECT] videoId=$videoId | container=$container | mimeType=$mimeType | codec=$codec | res=$res | fps=${vs.fps} | bitrate=$bitrate | type=PROGRESSIVE | resolver=NewPipe")

                progressiveList.add(mapOf(
                    "url" to vs.content,
                    "resolution" to res,
                    "width" to vs.width,
                    "height" to vs.height,
                    "container" to container,
                    "mimeType" to mimeType,
                    "codec" to codec,
                    "fps" to vs.fps,
                    "bitrate" to bitrate,
                    "isVideoOnly" to false,
                    "deliveryMethod" to "PROGRESSIVE",
                    "manifestType" to "PROGRESSIVE"
                ))
            }

            // 2. Adaptive Video-Only Streams (1080p, 1440p, 2160p 4K)
            val videoOnlyList = mutableListOf<Map<String, Any?>>()
            info.videoOnlyStreams?.filter { it.isUrl && !it.content.isNullOrBlank() }?.forEach { vs ->
                val container = vs.format?.suffix ?: "mp4"
                val mimeType = vs.format?.mimeType ?: "video/mp4"
                val codec = vs.codec ?: ""
                val res = vs.resolution ?: "${vs.height}p"
                val bitrate = vs.bitrate

                Log.d(TAG, "[STREAM-INSPECT] videoId=$videoId | container=$container | mimeType=$mimeType | codec=$codec | res=$res | fps=${vs.fps} | bitrate=$bitrate | type=VIDEO_ONLY | resolver=NewPipe")

                videoOnlyList.add(mapOf(
                    "url" to vs.content,
                    "resolution" to res,
                    "width" to vs.width,
                    "height" to vs.height,
                    "container" to container,
                    "mimeType" to mimeType,
                    "codec" to codec,
                    "fps" to vs.fps,
                    "bitrate" to bitrate,
                    "isVideoOnly" to true,
                    "deliveryMethod" to "DASH_ADAPTIVE",
                    "manifestType" to "ADAPTIVE_VIDEO_ONLY"
                ))
            }

            // 3. Audio-Only Streams (Opus 160kbps, AAC 128kbps)
            val audioList = mutableListOf<Map<String, Any?>>()
            info.audioStreams?.filter { it.isUrl && !it.content.isNullOrBlank() }?.forEach { as_ ->
                val container = as_.format?.suffix ?: "m4a"
                val mimeType = as_.format?.mimeType ?: "audio/mp4"
                val codec = as_.codec ?: ""
                val bitrate = as_.averageBitrate.takeIf { it > 0 } ?: as_.bitrate

                Log.d(TAG, "[STREAM-INSPECT] videoId=$videoId | container=$container | mimeType=$mimeType | codec=$codec | bitrate=$bitrate | type=AUDIO_ONLY | resolver=NewPipe")

                audioList.add(mapOf(
                    "url" to as_.content,
                    "container" to container,
                    "mimeType" to mimeType,
                    "codec" to codec,
                    "bitrate" to bitrate,
                    "deliveryMethod" to "DASH_ADAPTIVE"
                ))
            }

            // 4. Subtitles
            val subtitleList = mutableListOf<Map<String, Any?>>()
            info.subtitles?.filter { it.isUrl && !it.content.isNullOrBlank() }?.forEach { sub ->
                subtitleList.add(mapOf(
                    "url" to sub.content,
                    "languageName" to (sub.locale?.displayName ?: sub.displayLanguageName ?: "Unknown"),
                    "languageCode" to (sub.locale?.language ?: "en"),
                    "format" to (sub.format?.suffix ?: "vtt"),
                    "isAutoGenerated" to sub.isAutoGenerated
                ))
            }

            mapOf(
                "ok" to true,
                "videoId" to videoId,
                "title" to (info.name ?: "Unknown Title"),
                "uploader" to (info.uploaderName ?: "Unknown Channel"),
                "uploaderUrl" to (info.uploaderUrl ?: ""),
                "uploaderAvatarUrl" to (info.uploaderAvatars?.firstOrNull()?.url ?: ""),
                "durationSeconds" to info.duration,
                "isLive" to (info.streamType.name == "LIVE_STREAM" || info.streamType.name == "AUDIO_LIVE_STREAM"),
                "viewCount" to info.viewCount,
                "description" to (info.description?.content ?: ""),
                "thumbnailUrl" to (info.thumbnails?.maxByOrNull { it.height }?.url ?: ""),
                "dashMpdUrl" to (info.dashMpdUrl ?: ""),
                "hlsUrl" to (info.hlsUrl ?: ""),
                "progressiveStreams" to progressiveList,
                "videoOnlyStreams" to videoOnlyList,
                "audioStreams" to audioList,
                "subtitles" to subtitleList,
                "extractor" to "NewPipeExtractor/v0.26.5"
            )
        } catch (e: Throwable) {
            Log.e(TAG, "Extraction failed for $videoId: ${e.message}", e)
            mapOf(
                "ok" to false,
                "reason" to failureReason(e),
                "message" to (e.message ?: e.javaClass.simpleName)
            )
        }
    }
}
