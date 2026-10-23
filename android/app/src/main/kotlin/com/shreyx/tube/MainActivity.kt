package com.shreyx.tube

import android.os.Bundle
import android.os.IBinder
import android.content.Intent
import android.content.ComponentName
import android.content.ServiceConnection
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.cancel

class MainActivity : FlutterActivity() {

    private val scope = CoroutineScope(Dispatchers.Main)
    private var playerBridge: TubePlayerBridge? = null
    private var shortsPlayerBridge: TubeShortsPlayerBridge? = null
    private var notificationResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) TubeLinkBridge.accept(intent)
        super.onCreate(savedInstanceState)
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        TubeLinkBridge.accept(intent)
    }
    private var linkChannel: MethodChannel? = null
    private var bound = false
    private var playerChannel: MethodChannel? = null
    private val pending = mutableListOf<(TubePlayerBridge) -> Unit>()
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val service = (binder as TubePlaybackService.LocalBinder).service
            playerBridge = service.bridge.apply {
                activity = this@MainActivity
                methodChannel = playerChannel
            }
            TubePlayerPlatformView.attachActivePlayer()
            pending.toList().forEach { it(service.bridge) }
            pending.clear()
        }
        override fun onServiceDisconnected(name: ComponentName?) { playerBridge = null }
    }

    private fun withPlayer(action: (TubePlayerBridge) -> Unit) {
        val bridge = playerBridge
        if (bridge != null) action(bridge) else pending.add(action)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/device_setup")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(TubeDeviceSetup.status(this))
                    "requestNotifications" -> {
                        if (notificationResult != null) result.error("busy", "A permission request is already open", null)
                        else if (TubeDeviceSetup.canRequestNotifications(this)) {
                            notificationResult = result
                            TubeDeviceSetup.notificationAsked(this)
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), TubeDeviceSetup.NOTIFICATION_REQUEST)
                        } else if (TubeDeviceSetup.status(this)["notificationsEnabled"] == true) result.success(true)
                        else result.success(TubeDeviceSetup.openSettings(this, "openNotificationSettings"))
                    }
                    "openLinkSettings", "openYouTubeSettings", "openYouTubeMusicSettings", "openNotificationSettings", "openPipSettings" ->
                        result.success(TubeDeviceSetup.openSettings(this, call.method))
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/share")
            .setMethodCallHandler { call, result ->
                if (call.method == "shareVideo") result.success(TubeSharing.open(this,
                    call.argument<String>("url") ?: "", call.argument<String>("title") ?: "YouTube video"))
                else if (call.method == "shareText") result.success(TubeSharing.openText(this,
                    call.argument<String>("text") ?: "", call.argument<String>("title") ?: "Study materials"))
                else result.notImplemented()
            }

        linkChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/links").also { channel ->
            TubeLinkBridge.channel = channel
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pending" -> result.success(TubeLinkBridge.entries())
                    "ack" -> { TubeLinkBridge.acknowledge(call.argument<String>("id") ?: ""); result.success(true) }
                    "openYouTube" -> result.success(TubeLinkBridge.openYouTube(this, call.argument<String>("url") ?: ""))
                    "openLinkSettings" -> result.success(TubeLinkBridge.openSettings(this))
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/session_browser")
            .setMethodCallHandler { call, result ->
                if (call.method == "clear") {
                    try {
                        android.webkit.WebStorage.getInstance().deleteAllData()
                        android.webkit.WebView(this).apply {
                            clearCache(true)
                            clearHistory()
                            destroy()
                        }
                        android.webkit.CookieManager.getInstance().removeAllCookies {
                            android.webkit.CookieManager.getInstance().flush()
                            result.success(null)
                        }
                    } catch (_: Exception) {
                        result.error("browser_cleanup", "Sign-in browser cleanup failed", null)
                    }
                } else if (call.method == "openBrowser") {
                    result.success(TubeExternalBrowser.openYouTubeHome(this))
                } else result.notImplemented()
            }
        // 1. Initialize Media3 Player Bridge (Main Normal Player)
        val playerChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/player_channel")
        this.playerChannel = playerChannel
        bound = bindService(Intent(this, TubePlaybackService::class.java).setAction("com.shreyx.tube.LOCAL_PLAYER"),
            connection, BIND_AUTO_CREATE)

        // 2. Register PlatformView Factory for Media3 PlayerView (Main Player)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.shreyx.tube/player_view",
            TubePlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        // 3. Initialize Media3 Shorts Player Bridge & PlatformView
        val sBridge = TubeShortsPlayerBridge(applicationContext)
        val shortsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/shorts_player_channel")
        sBridge.methodChannel = shortsChannel
        shortsPlayerBridge = sBridge

        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.shreyx.tube/shorts_player_view",
            TubeShortsPlayerViewFactory(flutterEngine.dartExecutor.binaryMessenger)
        )

        // 4. Extraction MethodChannel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.shreyx.tube/native_extractor")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractVideoStreams" -> {
                        val videoId = call.argument<String>("videoId") ?: ""
                        scope.launch {
                            val data = withContext(Dispatchers.IO) {
                                TubeExtractor.extract(videoId)
                            }
                            result.success(data)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 5. Main Playback Control MethodChannel
        playerChannel.setMethodCallHandler { call, result ->
          withPlayer { bridge ->
            when (call.method) {
                "loadMedia" -> {
                    @Suppress("UNCHECKED_CAST")
                    val params = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val res = bridge.loadMedia(params)
                    result.success(res)
                }
                "play" -> {
                    bridge.play()
                    result.success(true)
                }
                "pause" -> {
                    bridge.pause()
                    result.success(true)
                }
                "seekTo" -> {
                    val pos = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    bridge.seekTo(pos)
                    result.success(true)
                }
                "seekToLive" -> {
                    bridge.seekToLive()
                    result.success(true)
                }
                "stop" -> {
                    bridge.stop()
                    result.success(true)
                }
                "setBrightness" -> {
                    val value = (call.argument<Number>("value"))?.toFloat()?.coerceIn(0.01f, 1f) ?: 0.5f
                    window.attributes = window.attributes.apply { screenBrightness = value }
                    result.success(true)
                }
                "setVolume" -> {
                    bridge.player?.volume = (call.argument<Number>("value"))?.toFloat()?.coerceIn(0f, 1f) ?: 0.7f
                    result.success(true)
                }
                "setSpeed" -> {
                    val speed = (call.argument<Double>("speed"))?.toFloat() ?: 1.0f
                    bridge.setSpeed(speed)
                    result.success(true)
                }
                "getStatus" -> {
                    result.success(bridge.getStatus())
                }
                "enterPip" -> {
                    result.success(bridge.enterPip())
                }
                else -> result.notImplemented()
            }
        }

        }

        // 6. Shorts Playback Control MethodChannel
        shortsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loadMedia" -> {
                    @Suppress("UNCHECKED_CAST")
                    val params = call.arguments as? Map<String, Any?> ?: emptyMap()
                    val res = sBridge.loadMedia(params)
                    result.success(res)
                }
                "play" -> {
                    sBridge.play()
                    result.success(true)
                }
                "pause" -> {
                    sBridge.pause()
                    result.success(true)
                }
                "stop" -> {
                    sBridge.stop()
                    result.success(true)
                }
                "seekTo" -> {
                    val pos = (call.argument<Number>("positionMs"))?.toLong() ?: 0L
                    sBridge.seekTo(pos)
                    result.success(true)
                }
                "setMuted" -> {
                    val muted = call.argument<Boolean>("muted") ?: false
                    sBridge.setMuted(muted)
                    result.success(true)
                }
                "getStatus" -> {
                    result.success(sBridge.getStatus())
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (playerBridge?.player?.isPlaying == true) {
            playerBridge?.enterPip()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == TubeDeviceSetup.NOTIFICATION_REQUEST) {
            // Denial is a valid user choice. Status is re-read by Flutter.
            notificationResult?.success(true)
            notificationResult = null
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: android.content.res.Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        playerBridge?.methodChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    override fun onDestroy() {
        notificationResult?.success(false)
        notificationResult = null
        scope.cancel()
        super.onDestroy()
        playerBridge?.apply {
            if (activity === this@MainActivity) {
                activity = null
                methodChannel = null
            }
        }
        linkChannel?.setMethodCallHandler(null)
        if (TubeLinkBridge.channel === linkChannel) TubeLinkBridge.channel = null
        playerChannel?.setMethodCallHandler(null)
        if (bound) { unbindService(connection); bound = false }
        pending.clear()
        playerBridge = null
        shortsPlayerBridge?.release()
        shortsPlayerBridge = null
    }
}
