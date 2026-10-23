package com.shreyx.tube

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.verify.domain.DomainVerificationManager
import android.content.pm.verify.domain.DomainVerificationUserState
import android.net.Uri
import android.os.Build
import android.provider.Settings

object TubeDeviceSetup {
    const val NOTIFICATION_REQUEST = 7041
    private fun preferences(activity: Activity) = activity.getSharedPreferences("tube_device_setup", 0)
    private fun targetPackage(activity: Activity, action: String): String = when (action) {
        "openYouTubeSettings" -> "com.google.android.youtube"
        "openYouTubeMusicSettings" -> "com.google.android.apps.youtube.music"
        else -> activity.packageName
    }
    private fun installed(activity: Activity, packageName: String): Boolean = try {
        activity.packageManager.getApplicationInfo(packageName, 0); true
    } catch (_: PackageManager.NameNotFoundException) { false }
    fun notificationAsked(activity: Activity) {
        preferences(activity).edit().putBoolean("notifications_asked", true).apply()
    }
    fun canRequestNotifications(activity: Activity): Boolean = Build.VERSION.SDK_INT >= 33 &&
        activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
        (!preferences(activity).getBoolean("notifications_asked", false) ||
            activity.shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))

    fun status(activity: Activity): Map<String, Any> {
        val domains = mutableMapOf<String, String>()
        var allowed = false
        if (Build.VERSION.SDK_INT >= 31) {
            try {
                val state = activity.getSystemService(DomainVerificationManager::class.java)
                    ?.getDomainVerificationUserState(activity.packageName)
                allowed = state?.isLinkHandlingAllowed == true
                state?.hostToStateMap?.forEach { (host, value) ->
                    domains[host] = when (value) {
                        DomainVerificationUserState.DOMAIN_STATE_VERIFIED -> "verified"
                        DomainVerificationUserState.DOMAIN_STATE_SELECTED -> "selected"
                        else -> "disabled"
                    }
                }
            } catch (_: Exception) { /* Status remains unknown, never report success. */ }
        }
        val pipSupported = Build.VERSION.SDK_INT >= 26 &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
        val pipEnabled = if (pipSupported) try {
            activity.getSystemService(AppOpsManager::class.java).checkOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE, android.os.Process.myUid(), activity.packageName
            ) == AppOpsManager.MODE_ALLOWED
        } catch (_: Exception) { false } else false
        return mapOf("available" to true,
            "notificationsEnabled" to activity.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
            "canRequestNotifications" to canRequestNotifications(activity),
            "linksSupported" to (Build.VERSION.SDK_INT >= 31), "linksAllowed" to allowed,
            "domains" to domains, "youtubeInstalled" to installed(activity, "com.google.android.youtube"),
            "youtubeMusicInstalled" to installed(activity, "com.google.android.apps.youtube.music"),
            "pipSupported" to pipSupported, "pipEnabled" to pipEnabled)
    }
    fun settingsIntent(activity: Activity, action: String): Intent? = when (action) {
        "openLinkSettings", "openYouTubeSettings", "openYouTubeMusicSettings" -> Intent(
            if (Build.VERSION.SDK_INT >= 31) Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS
                else Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${targetPackage(activity, action)}"))
        "openNotificationSettings" -> if (Build.VERSION.SDK_INT >= 26)
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${activity.packageName}"))
        "openPipSettings" -> if (Build.VERSION.SDK_INT >= 26)
            Intent("android.settings.PICTURE_IN_PICTURE_SETTINGS", Uri.parse("package:${activity.packageName}")) else null
        else -> null
    }
    fun openSettings(activity: Activity, action: String): Boolean {
        val intent = settingsIntent(activity, action) ?: return false
        return try { activity.startActivity(intent); true }
        catch (_: android.content.ActivityNotFoundException) {
            try {
                activity.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${targetPackage(activity, action)}")))
                true
            } catch (_: Exception) { false }
        }
        catch (_: SecurityException) { false }
    }
}
