package com.shreyx.tube

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.SystemClock
import io.flutter.plugin.common.MethodChannel

/** Process-local inbox: retained across Activity recreation, drained only after Flutter acknowledges. */
object TubeLinkBridge {
    private val pending = ArrayDeque<Map<String, String>>()
    private var lastUrl = ""
    private var lastAt = 0L
    var channel: MethodChannel? = null
    private val hosts = setOf("youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be")

    fun supportedUri(value: String): Uri? {
        if (value.length > 4096) return null
        val uri = Uri.parse(value)
        return uri.takeIf { it.scheme in setOf("https", "http") && it.host?.lowercase() in hosts && it.userInfo == null }
    }
    fun accept(intent: Intent?) {
        val url = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_SEND -> if (intent.type == "text/plain") {
                Regex("https?://[^\\s<>]+").findAll(intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: "")
                    .map { it.value.trimEnd('.', ',', ')', ']', ';') }.firstOrNull { supportedUri(it) != null }
            } else null
            else -> null
        } ?: return
        if (supportedUri(url) == null) return
        val now = SystemClock.elapsedRealtime()
        if (pending.any { it["url"] == url } || (lastUrl == url && now - lastAt < 1500)) return
        lastUrl = url
        lastAt = now
        if (pending.size == 16) pending.removeFirst()
        pending.addLast(mapOf("id" to SystemClock.elapsedRealtimeNanos().toString(), "url" to url))
        channel?.invokeMethod("incoming", null)
    }
    fun entries(): List<Map<String, String>> = pending.toList()
    fun acknowledge(id: String) { pending.removeAll { it["id"] == id } }

    fun openSettings(activity: Activity): Boolean {
        val uri = Uri.parse("package:${activity.packageName}")
        val action = if (android.os.Build.VERSION.SDK_INT >= 31)
            android.provider.Settings.ACTION_APP_OPEN_BY_DEFAULT_SETTINGS
            else android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        return try { activity.startActivity(Intent(action, uri)); true }
        catch (_: android.content.ActivityNotFoundException) { false }
        catch (_: SecurityException) { false }
    }

    fun openYouTube(activity: Activity, url: String): Boolean {
        val uri = supportedUri(url) ?: return false
        val yt = Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.youtube")
        try { activity.startActivity(yt); return true } catch (_: android.content.ActivityNotFoundException) { }
        catch (_: SecurityException) { }
        // Choose an actual browser, not our own matching deep-link Activity (no redirect loop).
        val browsers = activity.packageManager.queryIntentActivities(
            Intent(Intent.ACTION_VIEW, Uri.parse("https://example.com")).addCategory(Intent.CATEGORY_BROWSABLE),
            PackageManager.MATCH_DEFAULT_ONLY)
        for (candidate in browsers) {
            if (candidate.activityInfo.packageName == activity.packageName) continue
            val browser = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
                .setClassName(candidate.activityInfo.packageName, candidate.activityInfo.name)
            try { activity.startActivity(browser); return true } catch (_: android.content.ActivityNotFoundException) { }
            catch (_: SecurityException) { }
        }
        return false
    }
}
