package com.shreyx.tube

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.media3.common.MediaItem
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import io.flutter.plugin.common.MethodChannel

/**
 * Dedicated native Media3 ExoPlayer instance specifically for Shorts feed.
 * Features:
 * - Seamless looping (REPEAT_MODE_ONE)
 * - Mute / Unmute audio volume control
 * - Instant stop / clear when paging between shorts
 * - Isolated from the main video player
 */
class TubeShortsPlayerBridge(private val context: Context) : Player.Listener {

    companion object {
        private const val TAG = "TubeShortsPlayerBridge"
        @Volatile
        var instance: TubeShortsPlayerBridge? = null
    }

    var player: ExoPlayer? = null
        private set

    var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var isMuted: Boolean = false

    init {
        instance = this
        initPlayer()
    }

    private fun initPlayer() {
        if (player != null) return
        Log.i(TAG, "Initializing AndroidX Media3 ExoPlayer instance for Shorts...")
        player = ExoPlayer.Builder(context)
            .setLoadControl(DefaultLoadControl.Builder()
                .setBufferDurationsMs(10000, 20000, 750, 1500)
                .setPrioritizeTimeOverSizeThresholds(true).build())
            .build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
            setHandleAudioBecomingNoisy(true)
            addListener(this@TubeShortsPlayerBridge)
            repeatMode = Player.REPEAT_MODE_ONE // Seamless Shorts looping
            playWhenReady = false // NEVER autoplay in background on initialization
        }
        startProgressTracking()
    }

    private val dataSourceFactory: DefaultHttpDataSource.Factory by lazy {
        DefaultHttpDataSource.Factory()
            .setUserAgent(NoteNativeDownloader.USER_AGENT)
            .setConnectTimeoutMs(10000)
            .setReadTimeoutMs(15000)
            .setAllowCrossProtocolRedirects(true)
    }

    fun loadMedia(params: Map<String, Any?>): Map<String, Any?> {
        val videoUrl = params["videoUrl"] as? String ?: return mapOf("ok" to false, "message" to "No video URL")
        val audioUrl = params["audioUrl"] as? String
        val deliveryMethod = params["deliveryMethod"] as? String ?: "PROGRESSIVE"
        val mimeType = params["mimeType"] as? String
        val autoPlay = (params["autoPlay"] as? Boolean) ?: true

        Log.i(TAG, "Shorts loadMedia: deliveryMethod=$deliveryMethod, hasAudio=${!audioUrl.isNullOrBlank()}")

        try {
            val mediaSource: MediaSource = when {
                // HLS / Live
                deliveryMethod == "HLS" || mimeType?.contains("x-mpegURL", ignoreCase = true) == true -> {
                    HlsMediaSource.Factory(dataSourceFactory).createMediaSource(MediaItem.fromUri(videoUrl))
                }
                // DASH
                deliveryMethod == "DASH_MPD" || mimeType?.contains("dash+xml", ignoreCase = true) == true -> {
                    DashMediaSource.Factory(dataSourceFactory).createMediaSource(MediaItem.fromUri(videoUrl))
                }
                // Merging adaptive video + audio
                !audioUrl.isNullOrBlank() -> {
                    val videoSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(videoUrl))
                    val audioSource = ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(audioUrl))
                    MergingMediaSource(videoSource, audioSource)
                }
                // Progressive muxed
                else -> {
                    ProgressiveMediaSource.Factory(dataSourceFactory)
                        .createMediaSource(MediaItem.fromUri(videoUrl))
                }
            }

            player?.let { p ->
                p.stop()
                p.clearMediaItems()
                p.setMediaSource(mediaSource)
                p.volume = if (isMuted) 0f else 1f
                p.prepare()
                p.playWhenReady = autoPlay
            }

            return mapOf("ok" to true)
        } catch (e: Exception) {
            Log.e(TAG, "Error loading short media: ${e.message}", e)
            return mapOf("ok" to false, "message" to (e.message ?: "Failed to load short"))
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
    }

    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs)
    }

    fun setMuted(muted: Boolean) {
        isMuted = muted
        player?.volume = if (muted) 0f else 1f
    }

    fun getStatus(): Map<String, Any?> {
        val p = player ?: return mapOf(
            "isPlaying" to false,
            "isBuffering" to false,
            "positionMs" to 0L,
            "durationMs" to 0L,
            "isMuted" to isMuted
        )

        return mapOf(
            "isPlaying" to p.isPlaying,
            "isBuffering" to (p.playbackState == Player.STATE_BUFFERING),
            "playbackState" to stateToString(p.playbackState),
            "positionMs" to (if (p.currentPosition > 0) p.currentPosition else 0L),
            "durationMs" to (if (p.duration > 0) p.duration else 0L),
            "isMuted" to isMuted
        )
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
                mainHandler.postDelayed(this, 300)
            }
        }
        progressRunnable?.let { mainHandler.post(it) }
    }

    private fun stopProgressTracking() {
        progressRunnable?.let { mainHandler.removeCallbacks(it) }
        progressRunnable = null
    }

    // --- Player.Listener ---

    override fun onPlaybackStateChanged(playbackState: Int) {
        val stateStr = stateToString(playbackState)
        Log.d(TAG, "Shorts onPlaybackStateChanged: $stateStr (isPlaying=${player?.isPlaying})")
        mainHandler.post {
            methodChannel?.invokeMethod("onPlaybackStateChanged", mapOf(
                "state" to stateStr,
                "isPlaying" to (player?.isPlaying ?: false)
            ))
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        mainHandler.post {
            methodChannel?.invokeMethod("onIsPlayingChanged", isPlaying)
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        val isHttpError = error.cause is HttpDataSource.HttpDataSourceException
        val httpCode = (error.cause as? HttpDataSource.InvalidResponseCodeException)?.responseCode ?: -1
        Log.e(TAG, "Shorts onPlayerError: ${error.errorCodeName}, isHttp=$isHttpError, code=$httpCode", error)

        mainHandler.post {
            methodChannel?.invokeMethod("onPlaybackError", mapOf(
                "errorCode" to error.errorCodeName,
                "isHttpError" to isHttpError,
                "httpCode" to httpCode,
                "message" to (error.message ?: "Short playback error")
            ))
        }
    }

    fun release() {
        stopProgressTracking()
        player?.removeListener(this)
        player?.release()
        player = null
        instance = null
        Log.i(TAG, "TubeShortsPlayerBridge released")
    }
}
