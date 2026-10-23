package com.shreyx.tube

import android.app.Activity
import android.content.ClipData
import android.content.Intent

object TubeSharing {
    fun shareTextIntent(text: String, title: String): Intent? {
        if (text.isBlank() || text.length > 32000) return null
        return Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
            putExtra(Intent.EXTRA_SUBJECT, title.take(250))
            clipData = ClipData.newPlainText("Study materials", text)
        }, "Export study materials")
    }
    fun openText(activity: Activity, text: String, title: String): Boolean {
        val intent = shareTextIntent(text, title) ?: return false
        return try { activity.startActivity(intent); true }
        catch (_: android.content.ActivityNotFoundException) { false }
        catch (_: SecurityException) { false }
    }
    fun shareIntent(url: String, title: String): Intent? {
        if (TubeLinkBridge.supportedUri(url) == null) return null
        return Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, url)
            putExtra(Intent.EXTRA_SUBJECT, title.take(250))
            putExtra(Intent.EXTRA_TITLE, title.take(250))
            clipData = ClipData.newPlainText("YouTube video", url)
        }, "Share video")
    }
    fun open(activity: Activity, url: String, title: String): Boolean {
        val intent = shareIntent(url, title) ?: return false
        return try { activity.startActivity(intent); true }
        catch (_: android.content.ActivityNotFoundException) { false }
        catch (_: SecurityException) { false }
    }
}
