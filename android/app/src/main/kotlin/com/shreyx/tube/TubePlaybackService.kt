package com.shreyx.tube

import android.app.PendingIntent
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Binder
import android.os.IBinder
import android.util.Log
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.DefaultMediaNotificationProvider

/**
 * AndroidX Media3 MediaSessionService for ShreyX Tube background media playback.
 * Provides lock-screen media controls, Bluetooth / headset integration, and foreground
 * service lifecycle for normal video audio playback.
 */
class TubePlaybackService : MediaSessionService() {

    companion object {
        private const val TAG = "TubePlaybackService"
    }

    private var mediaSession: MediaSession? = null
    lateinit var bridge: TubePlayerBridge
        private set
    inner class LocalBinder : Binder() { val service get() = this@TubePlaybackService }
    private val localBinder = LocalBinder()
    override fun onBind(intent: Intent?): IBinder? =
        if (intent?.action == "com.shreyx.tube.LOCAL_PLAYER") localBinder else super.onBind(intent)

    fun endPlayback() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onCreate() {
        super.onCreate()
        bridge = TubePlayerBridge(this)
        val channelId = "tube_playback"
        setMediaNotificationProvider(DefaultMediaNotificationProvider.Builder(this)
            .setNotificationId(1001).setChannelId(channelId).build())
        Log.i(TAG, "TubePlaybackService onCreate: setting up MediaSession")

        val player = bridge.player
        if (player != null) {
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getActivity(this, 0, intent, flags)

            mediaSession = MediaSession.Builder(this, player)
                .setSessionActivity(pendingIntent)
                .build()
            Log.i(TAG, "MediaSession successfully initialized for TubePlayerBridge ExoPlayer")
        } else {
            Log.w(TAG, "TubePlayerBridge instance or player was null during service creation")
            stopSelf()
        }
    }

    private fun ensureForeground() {
        // Android's foreground deadline starts at startForegroundService(), even
        // when the stream is slow, unavailable, or paused. Do not wait for READY.
        val channelId = "tube_playback"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "Video playback", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val openApp = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else Notification.Builder(this)
        val notification = builder.setSmallIcon(R.drawable.ic_stat_play)
            .setContentTitle(bridge.player?.mediaMetadata?.title ?: "ShreyX Tube")
            .setContentText(bridge.player?.mediaMetadata?.artist ?: "Preparing playback")
            .setContentIntent(openApp)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(1001, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else startForeground(1001, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureForeground()
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        // Return existing session or lazily build if player became available
        if (mediaSession == null) {
            val player = bridge.player
            if (player != null) {
                val intent = Intent(this, MainActivity::class.java)
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pendingIntent = PendingIntent.getActivity(this, 0, intent, flags)
                mediaSession = MediaSession.Builder(this, player)
                    .setSessionActivity(pendingIntent)
                    .build()
            }
        }
        return mediaSession
    }

    override fun onDestroy() {
        Log.i(TAG, "TubePlaybackService onDestroy: releasing MediaSession")
        mediaSession?.run {
            release()
            mediaSession = null
        }
        bridge.release()
        super.onDestroy()
    }
}
