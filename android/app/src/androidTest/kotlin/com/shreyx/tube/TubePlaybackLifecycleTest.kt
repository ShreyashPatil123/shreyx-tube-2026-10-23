package com.shreyx.tube

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.session.MediaSessionManager
import android.os.Build
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Before
import org.junit.After
import org.junit.Test
import org.junit.Assert.*
import androidx.media3.common.Player
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Native device checks use app-private silent WAV fixtures without touching Flutter/profile stores. */
@Suppress("DEPRECATION")
class TubePlaybackLifecycleTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private lateinit var fixture: File
    private val context get() = instrumentation.targetContext
    private fun onMain(block: () -> Unit) = instrumentation.runOnMainSync(block)
    private fun waitFor(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.elapsedRealtime() + 10000
        while (SystemClock.elapsedRealtime() < deadline) {
            var ready = false
            onMain { ready = condition() }
            if (ready) return
            SystemClock.sleep(100)
        }
        fail(message)
    }
    @Before fun setUp() {
        fixture = File(context.cacheDir, "tube-native-lifecycle-test.wav")
        val length = 8000 * 2 * 40
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray()).putInt(length + 36).put("WAVEfmt ".toByteArray())
        header.putInt(16).putShort(1).putShort(1).putInt(8000).putInt(16000).putShort(2).putShort(16)
        header.put("data".toByteArray()).putInt(length)
        fixture.outputStream().use { it.write(header.array()); it.write(ByteArray(length)) }
        val intent = Intent(context, TubePlaybackService::class.java)
        if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        waitFor("Service player was not created") { TubePlayerBridge.instance?.player != null }
        onMain {
            TubePlayerBridge.instance!!.loadMedia(mapOf("videoUrl" to fixture.toURI().toString(),
                "videoId" to "native-test", "title" to "Native lifecycle test", "channelTitle" to "ShreyX Tube test",
                "mimeType" to "audio/wav", "autoPlay" to true))
        }
        waitFor("Silent fixture did not start") { TubePlayerBridge.instance?.player?.isPlaying == true }
    }
    @After fun tearDown() {
        onMain { TubePlayerBridge.instance?.stop() }
        context.stopService(Intent(context, TubePlaybackService::class.java))
        waitFor("Service was not released after stop") { TubePlayerBridge.instance == null }
        fixture.delete()
    }
    @Test fun testPlaybackSurvivesNoActivityAndScreenOff() {
        val player = TubePlayerBridge.instance!!.player!!
        var before = 0L
        onMain { assertNull(TubePlayerBridge.instance!!.activity); before = player.currentPosition }
        instrumentation.uiAutomation.executeShellCommand("input keyevent 223").close()
        try {
            SystemClock.sleep(2500)
            onMain {
                assertSame(player, TubePlayerBridge.instance!!.player)
                assertTrue(player.isPlaying)
                assertTrue(player.currentPosition > before + 1000)
            }
        } finally { instrumentation.uiAutomation.executeShellCommand("input keyevent 224").close() }
    }
    @Test fun testSurfaceHandoffsKeepOnePlayerAndPosition() {
        val player = TubePlayerBridge.instance!!.player!!
        onMain {
            val before = player.currentPosition
            repeat(8) { index ->
                val view = TubePlayerPlatformView(context, index, null)
                assertSame(player, TubePlayerBridge.instance!!.player)
                val playerView = (view.getView() as android.widget.FrameLayout).getChildAt(0) as androidx.media3.ui.PlayerView
                assertTrue(playerView.videoSurfaceView is android.view.TextureView)
                view.dispose()
            }
            assertTrue(player.currentPosition >= before)
            assertEquals(1, player.mediaItemCount)
            assertEquals(Player.STATE_READY, player.playbackState)
        }
    }
    @Test fun testActivityRecreationKeepsServicePlayer() {
        val player = TubePlayerBridge.instance!!.player!!
        onMain { player.pause(); player.seekTo(1500) }
        context.startActivity(Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        waitFor("Activity did not attach to service") { TubePlayerBridge.instance?.activity != null }
        val activity = TubePlayerBridge.instance!!.activity!!
        onMain { activity.recreate() }
        waitFor("Recreated Activity did not reconnect") {
            val next = TubePlayerBridge.instance?.activity
            next != null && next !== activity
        }
        onMain {
            assertSame(player, TubePlayerBridge.instance!!.player)
            assertEquals(1500L, player.currentPosition)
            assertFalse(player.playWhenReady)
            TubePlayerBridge.instance!!.activity?.finish()
        }
    }
    @Test fun testNoisyRoutePausesPlayback() {
        // Android 16 protects this system broadcast even from adb shell. Exercise the
        // real registered Media3 receiver directly; physical headset removal is separate QA.
        onMain {
            val player = TubePlayerBridge.instance!!.player!!
            val managerField = player.javaClass.getDeclaredField("audioBecomingNoisyManager").apply { isAccessible = true }
            val manager = managerField.get(player)!!
            val receiverField = manager.javaClass.getDeclaredField("receiver").apply { isAccessible = true }
            (receiverField.get(manager) as android.content.BroadcastReceiver).onReceive(context,
                Intent(android.media.AudioManager.ACTION_AUDIO_BECOMING_NOISY))
        }
        waitFor("Noisy route did not pause playback") { TubePlayerBridge.instance?.player?.playWhenReady == false }
    }
    @Test fun testMediaSessionMetadataAndExternalTransport() {
        val manager = context.getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
        instrumentation.uiAutomation.adoptShellPermissionIdentity("android.permission.MEDIA_CONTENT_CONTROL")
        try {
            val controller = manager.getActiveSessions(null as ComponentName?).first { it.packageName == context.packageName }
            assertEquals("Native lifecycle test", controller.metadata?.getString(android.media.MediaMetadata.METADATA_KEY_TITLE))
            controller.transportControls.pause()
            waitFor("External pause did not reach player") { TubePlayerBridge.instance?.player?.playWhenReady == false }
            controller.transportControls.play()
            waitFor("External play did not reach player") { TubePlayerBridge.instance?.player?.isPlaying == true }
        } finally { instrumentation.uiAutomation.dropShellPermissionIdentity() }
    }
    @Test fun testTransientAudioFocusLossPausesAndRecovers() {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        val listener = android.media.AudioManager.OnAudioFocusChangeListener { }
        val request = android.media.AudioFocusRequest.Builder(android.media.AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_MEDIA).build())
            .setOnAudioFocusChangeListener(listener, android.os.Handler(android.os.Looper.getMainLooper())).build()
        assertEquals(android.media.AudioManager.AUDIOFOCUS_REQUEST_GRANTED, audio.requestAudioFocus(request))
        try { waitFor("Transient focus loss did not pause") { TubePlayerBridge.instance?.player?.isPlaying == false } }
        finally { audio.abandonAudioFocusRequest(request) }
        waitFor("Audio focus gain did not resume") { TubePlayerBridge.instance?.player?.isPlaying == true }
    }
    @Test fun testStopClearsMediaAndReleasesUnboundService() {
        val player = TubePlayerBridge.instance!!.player!!
        onMain { TubePlayerBridge.instance!!.stop(); assertEquals(0, player.mediaItemCount) }
        waitFor("Stopped unbound service retained player") { TubePlayerBridge.instance == null }
    }

}
