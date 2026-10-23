package com.shreyx.tube

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class TubeLinkIntentTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun clearInbox() { TubeLinkBridge.entries().forEach { TubeLinkBridge.acknowledge(it["id"]!!) } }
    @Before fun before() { instrumentation.runOnMainSync { clearInbox() } }
    @After fun after() { instrumentation.runOnMainSync { clearInbox() } }

    @Test fun supportedFiltersAppearInAndroidCandidateResolution() {
        val links = listOf("https://youtube.com/watch?v=abcdefghijk", "https://www.youtube.com/watch?v=abcdefghijk&t=90",
            "http://m.youtube.com/watch?v=abcdefghijk", "https://youtu.be/abcdefghijk", "https://youtube.com/shorts/abcdefghijk",
            "https://youtube.com/live/abcdefghijk", "https://music.youtube.com/watch?v=abcdefghijk")
        for (url in links) {
            val candidates = context.packageManager.queryIntentActivities(Intent(Intent.ACTION_VIEW, Uri.parse(url))
                .addCategory(Intent.CATEGORY_BROWSABLE), PackageManager.MATCH_ALL)
            assertTrue(url, candidates.any { it.activityInfo.packageName == context.packageName })
        }
    }
    private fun waitUntil(message: String, condition: () -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 10000
        while (SystemClock.elapsedRealtime() < end) {
            var ready = false
            instrumentation.runOnMainSync { ready = condition() }
            if (ready) return
            SystemClock.sleep(100)
        }
        fail(message)
    }
    @Test fun coldViewLaunchRetainsOriginalLinkUntilAcknowledged() {
        val url = "https://youtu.be/coldlink001?t=1m30s"
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW).setData(Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        try {
            instrumentation.runOnMainSync {
                assertEquals(url, activity.intent.dataString)
                assertEquals(url, TubeLinkBridge.entries().single()["url"])
            }
        } finally { instrumentation.runOnMainSync { activity.finish() } }
    }
    @Test fun warmIntentsDeduplicateAndSurviveActivityRecreation() {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        val first = "https://www.youtube.com/watch?v=warmlink001&t=0"
        val second = "https://youtube.com/shorts/warmlink002?si=share"
        try {
            waitUntil("Service did not attach to warm Activity") { TubePlayerBridge.instance?.activity === activity }
            for (url in listOf(first, first, second)) {
                instrumentation.runOnMainSync { activity.startActivity(Intent(activity, MainActivity::class.java)
                    .setAction(Intent.ACTION_VIEW).setData(Uri.parse(url))
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)) }
                waitUntil("Warm intent not delivered") { activity.intent.dataString == url }
            }
            instrumentation.runOnMainSync {
                assertEquals(2, TubeLinkBridge.entries().size)
                TubeLinkBridge.acknowledge(TubeLinkBridge.entries().first()["id"]!!)
                activity.recreate()
            }
            waitUntil("Recreated Activity did not attach") {
                val restored = TubePlayerBridge.instance?.activity
                restored is MainActivity && restored !== activity
            }
            instrumentation.runOnMainSync { assertEquals(listOf(second), TubeLinkBridge.entries().map { it["url"] }) }
        } finally { instrumentation.runOnMainSync { TubePlayerBridge.instance?.activity?.finish(); activity.finish() } }
    }
    @Test fun genericFailuresAndForeignLinksDoNotBecomeMembersOnlyOrLaunch() {
        assertEquals("network_failed", TubeExtractor.failureReason(java.io.IOException("403 members-only title")))
        assertEquals("extraction_failed", TubeExtractor.failureReason(IllegalStateException("join this channel")))
        instrumentation.runOnMainSync {
            TubeLinkBridge.accept(Intent(Intent.ACTION_VIEW, Uri.parse("https://youtube.com.evil/watch?v=abcdefghijk")))
            assertTrue(TubeLinkBridge.entries().isEmpty())
        }
    }
}
