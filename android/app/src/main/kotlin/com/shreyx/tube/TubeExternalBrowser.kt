package com.shreyx.tube

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri

object TubeExternalBrowser {
    /** Resolve a generic web address first so YouTube's own App Link handler
     * cannot intercept this explicit request to open the user's browser. */
    fun openYouTubeHome(context: Context): Boolean {
        val probe = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.example.com/"))
            .addCategory(Intent.CATEGORY_BROWSABLE)
        val resolved = context.packageManager.resolveActivity(probe, PackageManager.MATCH_DEFAULT_ONLY)
        val defaultPackage = resolved?.activityInfo?.packageName
        val target = Intent(Intent.ACTION_VIEW, Uri.parse("https://m.youtube.com/"))
            .addCategory(Intent.CATEGORY_BROWSABLE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            if (defaultPackage != null && defaultPackage != "android" && defaultPackage != context.packageName) {
                target.setPackage(defaultPackage)
                context.startActivity(target)
            } else {
                val browsers = context.packageManager.queryIntentActivities(probe, PackageManager.MATCH_ALL)
                    .filter { it.activityInfo.packageName != context.packageName && it.activityInfo.packageName != "com.google.android.youtube" }
                if (browsers.isEmpty()) return false
                val choices = browsers.map { Intent(target).setPackage(it.activityInfo.packageName) }
                val chooser = Intent.createChooser(choices.first(), "Open YouTube in browser")
                    .putExtra(Intent.EXTRA_INITIAL_INTENTS, choices.drop(1).toTypedArray())
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(chooser)
            }
            true
        } catch (_: Exception) { false }
    }
}
