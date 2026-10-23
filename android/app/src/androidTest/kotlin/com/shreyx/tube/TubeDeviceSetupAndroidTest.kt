package com.shreyx.tube

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.content.pm.verify.domain.DomainVerificationManager
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test

class TubeDeviceSetupAndroidTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private fun withActivity(block: (MainActivity) -> Unit) {
        val activity = instrumentation.startActivitySync(Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) as MainActivity
        try { instrumentation.runOnMainSync { block(activity) } }
        finally { instrumentation.runOnMainSync { activity.finish() } }
    }
    @Test fun statusMatchesAndroidDomainStateWithoutChangingIt() = withActivity { activity ->
        val status = TubeDeviceSetup.status(activity)
        assertEquals(true, status["available"])
        if (Build.VERSION.SDK_INT >= 31) {
            val system = activity.getSystemService(DomainVerificationManager::class.java)
                .getDomainVerificationUserState(activity.packageName)!!
            assertEquals(system.isLinkHandlingAllowed, status["linksAllowed"])
            val domains = status["domains"] as Map<*, *>
            assertEquals(system.hostToStateMap.keys, domains.keys)
            assertTrue(domains.containsKey("youtube.com"))
            assertTrue(domains.containsKey("youtu.be"))
        }
    }
    @Test fun setupSettingsUseTheCorrectAppAndDoNotClaimDomainOwnership() = withActivity { activity ->
        val own = TubeDeviceSetup.settingsIntent(activity, "openLinkSettings")!!
        val youtube = TubeDeviceSetup.settingsIntent(activity, "openYouTubeSettings")!!
        assertEquals(Uri.parse("package:com.shreyx.tube"), own.data)
        assertEquals(Uri.parse("package:com.google.android.youtube"), youtube.data)
        assertEquals(Uri.parse("package:com.google.android.apps.youtube.music"),
            TubeDeviceSetup.settingsIntent(activity, "openYouTubeMusicSettings")!!.data)
        assertEquals(if (Build.VERSION.SDK_INT >= 31) Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS
            else Settings.ACTION_APPLICATION_DETAILS_SETTINGS, own.action)
        assertEquals(own.action, youtube.action)
        assertNull(TubeDeviceSetup.settingsIntent(activity, "unrelatedAction"))
        assertNull(own.component)
    }
    @Test fun notificationAndPipSettingsOnlyTargetShreyX() = withActivity { activity ->
        val notifications = TubeDeviceSetup.settingsIntent(activity, "openNotificationSettings")!!
        if (Build.VERSION.SDK_INT >= 26) {
            assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, notifications.action)
            assertEquals(activity.packageName, notifications.getStringExtra(Settings.EXTRA_APP_PACKAGE))
            val pip = TubeDeviceSetup.settingsIntent(activity, "openPipSettings")!!
            assertEquals("android.settings.PICTURE_IN_PICTURE_SETTINGS", pip.action)
            assertEquals(Uri.parse("package:com.shreyx.tube"), pip.data)
        }
    }
}
