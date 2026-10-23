package com.shreyx.tube

import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class TubeUsabilityAndroidTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test fun studyMaterialsExportAsBoundedPlainTextWithoutChoosingARecipient() {
        val text = "# Study notes\nSource 00:12: Active recall uses retrieval."
        val chooser = TubeSharing.shareTextIntent(text, "Study fixture")!!
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("text/plain", send.type)
        assertEquals(text, send.getStringExtra(Intent.EXTRA_TEXT))
        assertEquals(text, send.clipData!!.getItemAt(0).text.toString())
        assertNull(send.`package`)
        assertNull(send.component)
        assertNull(TubeSharing.shareTextIntent(" ", "Fixture"))
        assertNull(TubeSharing.shareTextIntent("x".repeat(32001), "Fixture"))
    }

    @Test fun sharesheetCarriesTheVideoWithoutSendingToAPreselectedDestination() {
        val url = "https://youtu.be/abcdefghijk?t=30"
        val chooser = TubeSharing.shareIntent(url, "Fixture title")!!
        assertEquals(Intent.ACTION_CHOOSER, chooser.action)
        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
        assertEquals(Intent.ACTION_SEND, send.action)
        assertEquals("text/plain", send.type)
        assertEquals(url, send.getStringExtra(Intent.EXTRA_TEXT))
        assertEquals("Fixture title", send.getStringExtra(Intent.EXTRA_SUBJECT))
        assertEquals(url, send.clipData!!.getItemAt(0).text.toString())
        assertNull(send.`package`)
        assertNull(send.component)
        assertNull(TubeSharing.shareIntent("https://youtube.com.evil/watch?v=abcdefghijk", "Fixture"))
    }
    @Test fun sharedVideoLinksEnterTheExistingChoiceInbox() {
        instrumentation.runOnMainSync {
            TubeLinkBridge.entries().forEach { TubeLinkBridge.acknowledge(it["id"]!!) }
            val intent = Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "Watch this: https://youtu.be/sharedlink1?t=30.")
            TubeLinkBridge.accept(intent)
            TubeLinkBridge.accept(intent)
            assertEquals(listOf("https://youtu.be/sharedlink1?t=30"), TubeLinkBridge.entries().map { it["url"] })
            TubeLinkBridge.entries().forEach { TubeLinkBridge.acknowledge(it["id"]!!) }
            TubeLinkBridge.accept(Intent(Intent.ACTION_SEND).setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "https://example.com/ordinary-link"))
            assertTrue(TubeLinkBridge.entries().isEmpty())
        }
        val candidates = context.packageManager.queryIntentActivities(
            Intent(Intent.ACTION_SEND).setType("text/plain"), PackageManager.MATCH_ALL)
        assertTrue(candidates.any { it.activityInfo.packageName == context.packageName })
    }
    @Test fun launcherUsesTheNewAdaptiveVideoIcon() {
        val icon = context.applicationInfo.loadIcon(context.packageManager)
        assertTrue(icon is AdaptiveIconDrawable)
        val bitmap = Bitmap.createBitmap(108,108,Bitmap.Config.ARGB_8888)
        icon.setBounds(0,0,108,108)
        icon.draw(Canvas(bitmap))
        val center = bitmap.getPixel(54,54)
        assertTrue(android.graphics.Color.red(center) > 230)
        assertTrue(android.graphics.Color.green(center) > 230)
        assertTrue(android.graphics.Color.blue(center) > 230)
        bitmap.recycle()
    }
}
