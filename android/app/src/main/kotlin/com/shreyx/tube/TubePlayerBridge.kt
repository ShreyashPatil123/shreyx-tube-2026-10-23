package com.shreyx.tube

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Rational
import androidx.media3.common.MediaItem
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.MethodChannel

/**
 * Native Media3 (ExoPlayer) playback bridge.
 * Supports progressive muxed streams, adaptive merging of 1080p+ video-only and audio streams,
 * DASH, HLS, seeking, and Picture-in-Picture.
 */
class TubePlayerBridge(private val context: Context) : Player.Listener {

    companion object {
        private const val TAG = "TubePlayerBridge"
        @Volatile
        var instance: TubePlayerBridge? = null
    }

    var player: ExoPlayer? = null
        private set

    var methodChannel: MethodChannel? = null
    var activity: Activity? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null

    private var currentVideoWidth = 0
    private var currentVideoHeight = 0
    private var loadStartedAt = 0L
    private var bufferStartedAt = 0L
    private var hasPlayed = false
    private var rebufferCount = 0
    private var rebufferMs = 0L

    init {
        instance = this
        initPlayer()
    }

    private fun initPlayer() {
        if (player != null) return
        Log.i(TAG, "Initializing AndroidX Media3 ExoPlayer instance...")
        val trackSelector = DefaultTrackSelector(context).apply {
            setParameters(buildUponParameters().setMaxVideoSize(1920, 1080))
        }
        player = ExoPlayer.Builder(context)
            .setTrackSelector(trackSelector)
            .setLoadControl(DefaultLoadControl.Builder()
                .setBufferDurationsMs(30000, 60000, 1000, 3000)
                .setPrioritizeTimeOverSizeThresholds(true).build())
            .build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
            setHandleAudioBecomingNoisy(true)
            addListener(this@TubePlayerBridge)
            playWhenReady = false
            setWakeMode(C.WAKE_MODE_NETWORK)
        }
        startProgressTracking()
    }

    private val dataSourceFactory: DefaultDataSource.Factory by lazy {
        val http = DefaultHttpDataSource.Factory()
            .setUserAgent(NoteNativeDownloader.USER_AGENT)
            .setConnectTimeoutMs(15000)
            .setReadTimeoutMs(20000)
            .setAllowCrossProtocolRedirects(true)
        DefaultDataSource.Factory(context, http)
    }

    fun loadMedia(params: Map<String, Any?>): Map<String, Any?> {
        val videoUrl = params["videoUrl"] as? String ?: return mapOf("ok" to false, "message" to "No video URL")
        val audioUrl = params["audioUrl"] as? String
        val deliveryMethod = params["deliveryMethod"] as? String ?: "PROGRESSIVE"
        val mimeType = params["mimeType"] as? String
        val startPositionMs = (params["startPositionMs"] as? Number)?.toLong() ?: 0L
        val autoPlay = (params["autoPlay"] as? Boolean) ?: true
        loadStartedAt = android.os.SystemClock.elapsedRealtime()
        bufferStartedAt = 0L
        hasPlayed = false
        rebufferCount = 0
        rebufferMs = 0L

        val title = params["title"] as? String ?: "ShreyX Video"
        val channelTitle = params["channelTitle"] as? String ?: "YouTube"

        Log.i(TAG, "Loading Media: title=$title, deliveryMethod=$deliveryMethod, mimeType=$mimeType, hasAudio=${!audioUrl.isNullOrBlank()}, startPos=${startPositionMs}ms")
        val isLive = params["isLive"] == true
        (player?.trackSelector as? DefaultTrackSelector)?.apply {
            setParameters(buildUponParameters().setMaxVideoSize(
                if (isLive) 1280 else 1920, if (isLive) 720 else 1080))
        }

        try {
            val metadata = androidx.media3.common.MediaMetadata.Builder()
                .setExtras(android.os.Bundle().apply { putBoolean("requiresAccount", params["requiresAccount"] == true) })
                .setTitle(title)
                .setArtist(channelTitle)
                .setDisplayTitle(title)
                .setArtworkUri((params["thumbnailUrl"] as? String)?.takeIf { it.isNotBlank() }?.let { android.net.Uri.parse(it) })
                .build()
            val manifestItem = MediaItem.Builder().setMediaId(params["videoId"] as? String ?: "").setUri(videoUrl).setMediaMetadata(metadata)
                .apply {
                    if (isLive) setLiveConfiguration(MediaItem.LiveConfiguration.Builder()
                        .setTargetOffsetMs(3000).setMinOffsetMs(1000).setMaxOffsetMs(6000)
                        .setMinPlaybackSpeed(0.97f).setMaxPlaybackSpeed(1.05f).build())
                }.build()

            val mediaSource: MediaSource = when {
                // 1. HLS / Live
                deliveryMethod == "HLS" || mimeType?.contains("x-mpegURL", ignoreCase = true) == true -> {
                    Log.i(TAG, "Constructing HlsMediaSource")
                    HlsMediaSource.Factory(dataSourceFactory).createMediaSource(
                        manifestItem
                    )
                }
                // 2. DASH Manifest
                deliveryMethod == "DASH_MPD" || mimeType?.contains("dash+xml", ignoreCase = true) == true -> {
                    Log.i(TAG, "Constructing DashMediaSource")
                    DashMediaSource.Factory(dataSourceFactory).createMediaSource(
                        manifestItem
                    )
                }
                // 3. Adaptive Video-Only + Audio-Only (1080p, 1440p, 4K)
                !audioUrl.isNullOrBlank() -> {
                    Log.i(TAG, "Constructing MergingMediaSource for adaptive video + audio")
                    val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(manifestItem)
                    val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.Builder().setUri(audioUrl).setMediaMetadata(metadata).build())
                    MergingMediaSource(videoSource, audioSource)
                }
                // 4. Progressive Muxed (360p / 720p)
                else -> {
                    Log.i(TAG, "Constructing ProgressiveMediaSource")
                    ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(manifestItem)
                }
            }

            player?.let { p ->
                p.stop()
                p.clearMediaItems()
                p.playlistMetadata = metadata
                p.setMediaSource(mediaSource)
                p.prepare()
                if (isLive) {
                    p.seekToDefaultPosition()
                } else if (startPositionMs > 0) {
                    p.seekTo(startPositionMs)
                }
                p.playWhenReady = autoPlay
            }

            // Start background MediaSessionService for normal video audio continuity
            try {
                val serviceIntent = Intent(context, TubePlaybackService::class.java)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Could not start TubePlaybackService: ${e.message}")
            }

            return mapOf("ok" to true)
        } catch (e: Exception) {
            Log.e(TAG, "Error loading media into Media3: ${e.message}", e)
            return mapOf("ok" to false, "message" to (e.message ?: "Failed to load media"))
        }
    }

    fun play() {
        player?.play()
    }

    fun pause() {
        player?.pause()
    }

    fun stop() {
        player?.stop()
        player?.clearMediaItems()
        (context as? TubePlaybackService)?.endPlayback()
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs)
    }

    fun seekToLive() {
        alignToLiveEdge()
        player?.play()
    }

    private fun alignToLiveEdge() {
        val p = player ?: return
        val offset = p.currentLiveOffset
        if (offset != C.TIME_UNSET && p.duration > 1000) {
            // HLS default positions can start several segments behind the
            // requested offset. Seek within the available window, keeping a
            // second of headroom rather than waiting for speed catch-up.
            val target = (p.currentPosition + offset - 3000)
                .coerceIn(0L, p.duration - 1000)
            if (target > p.currentPosition + 500) p.seekTo(target)
        } else {
            p.seekToDefaultPosition()
        }
    }

    fun setSpeed(speed: Float) {
        player?.setPlaybackSpeed(speed)
    }

    fun getStatus(): Map<String, Any?> {
        val p = player ?: return mapOf(
            "isPlaying" to false,
            "isBuffering" to false,
            "positionMs" to 0L,
            "durationMs" to 0L,
            "bufferedMs" to 0L,
            "videoWidth" to 0,
            "videoHeight" to 0
        )

        val duration = if (p.duration > 0) p.duration else 0L
        val position = if (p.currentPosition > 0) p.currentPosition else 0L
        val buffered = if (p.bufferedPosition > 0) p.bufferedPosition else 0L

        return mapOf(
            "videoId" to p.currentMediaItem?.mediaId,
            "title" to p.mediaMetadata.title?.toString(),
            "channelTitle" to p.mediaMetadata.artist?.toString(),
            "thumbnailUrl" to p.mediaMetadata.artworkUri?.toString(),
            "isLive" to p.isCurrentMediaItemLive,
            "hasMedia" to (p.mediaItemCount > 0),
            "requiresAccount" to (p.mediaMetadata.extras?.getBoolean("requiresAccount", false) == true),
            "isPlaying" to p.isPlaying,
            "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
            "playbackState" to stateToString(p.playbackState),
            "positionMs" to position,
            "durationMs" to duration,
            "bufferedMs" to buffered,
            "videoWidth" to currentVideoWidth,
            "videoHeight" to currentVideoHeight
        )
    }

    fun enterPip(): Boolean {
        val act = activity ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val width = if (currentVideoWidth > 0) currentVideoWidth else 16
            val height = if (currentVideoHeight > 0) currentVideoHeight else 9
            val aspect = (width.toDouble() / height).coerceIn(1.0 / 2.38, 2.38)
            val rational = Rational((aspect * 1000).toInt(), 1000)
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(rational)
                .build()
            return try { act.enterPictureInPictureMode(params) }
                catch (error: RuntimeException) {
                    Log.w(TAG, "Picture-in-picture unavailable: ${error.message}")
                    false
                }
        }
        return false
    }

    private fun stateToString(state: Int): String {
        return when (state) {
            Player.STATE_IDLE -> "IDLE"
            Player.STATE_BUFFERING -> "BUFFERING"
            Player.STATE_READY -> "READY"
            Player.STATE_ENDED -> "ENDED"
            else -> "UNKNOWN"
        }
    }

    private fun startProgressTracking() {
        stopProgressTracking()
        progressRunnable = object : Runnable {
            override fun run() {
                val p = player
                if (p != null && (p.isPlaying || p.playbackState == Player.STATE_BUFFERING)) {
                    val status = getStatus()
                    mainHandler.post {
                        methodChannel?.invokeMethod("onProgressUpdate", status)
                    }
                }
                mainHandler.postDelayed(this, 500)
            }
        }
        progressRunnable?.let { mainHandler.post(it) }
    }

    private fun stopProgressTracking() {
        progressRunnable?.let { mainHandler.removeCallbacks(it) }
        progressRunnable = null
    }

    // --- Player.Listener Implementation ---

    override fun onPlaybackStateChanged(playbackState: Int) {
        val stateStr = stateToString(playbackState)
        Log.i(TAG, "onPlaybackStateChanged: $stateStr (isPlaying=${player?.isPlaying})")
        val now = android.os.SystemClock.elapsedRealtime()
        if (playbackState == Player.STATE_BUFFERING) {
            bufferStartedAt = now
            if (hasPlayed) rebufferCount++
        } else if (playbackState == Player.STATE_READY && bufferStartedAt > 0L) {
            val elapsed = now - bufferStartedAt
            if (hasPlayed) rebufferMs += elapsed
            Log.i(TAG, "Buffer ready: startup=${!hasPlayed}, waitMs=$elapsed, rebufferCount=$rebufferCount, totalRebufferMs=$rebufferMs, sinceLoadMs=${now-loadStartedAt}")
            bufferStartedAt = 0L
        }
        if (playbackState == Player.STATE_READY && player?.isCurrentMediaItemLive == true) {
            Log.i(TAG, "Live offset: ${player?.currentLiveOffset}ms (target 3000ms)")
        }
        mainHandler.post {
            methodChannel?.invokeMethod("onPlaybackStateChanged", mapOf(
                "state" to stateStr,
                "isPlaying" to (player?.isPlaying ?: false)
            ))
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (isPlaying) hasPlayed = true
        Log.i(TAG, "onIsPlayingChanged: $isPlaying")
        mainHandler.post {
            methodChannel?.invokeMethod("onIsPlayingChanged", isPlaying)
        }
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        currentVideoWidth = videoSize.width
        currentVideoHeight = videoSize.height
        Log.i(TAG, "onVideoSizeChanged: ${videoSize.width}x${videoSize.height}")
        mainHandler.post {
            methodChannel?.invokeMethod("onVideoSizeChanged", mapOf(
                "width" to videoSize.width,
                "height" to videoSize.height,
                "pixelAspectRatio" to videoSize.pixelWidthHeightRatio
            ))
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            player?.seekToDefaultPosition()
            player?.prepare()
            return
        }
        val lastPos = player?.currentPosition ?: 0L
        val isHttpError = error.cause is HttpDataSource.HttpDataSourceException
        val httpCode = (error.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode ?: -1

        Log.e(TAG, "onPlayerError: code=${error.errorCode}, isHttp=$isHttpError, httpCode=$httpCode, pos=${lastPos}ms: ${error.message}", error)

        mainHandler.post {
            methodChannel?.invokeMethod("onPlaybackError", mapOf(
                "errorCode" to error.errorCodeName,
                "isHttpError" to isHttpError,
                "httpCode" to httpCode,
                "lastPositionMs" to lastPos,
                "message" to (error.message ?: "Playback error")
            ))
        }
    }

    fun release() {
        methodChannel = null
        activity = null
        stopProgressTracking()
        player?.removeListener(this)
        player?.release()
        player = null
        instance = null
        Log.i(TAG, "TubePlayerBridge released")
    }
}
