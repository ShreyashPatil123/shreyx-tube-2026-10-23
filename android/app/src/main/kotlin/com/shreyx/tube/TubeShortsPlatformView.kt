package com.shreyx.tube

import android.content.Context
import android.graphics.Color
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * PlatformView embedding AndroidX Media3 PlayerView for vertical Shorts.
 * Configured with RESIZE_MODE_ZOOM so 9:16 Shorts seamlessly fill the viewport.
 */
class TubeShortsPlatformView(
    context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView {

    private val container: FrameLayout = object : FrameLayout(context) {
        override fun dispatchTouchEvent(ev: android.view.MotionEvent?): Boolean = false
        override fun onInterceptTouchEvent(ev: android.view.MotionEvent?): Boolean = false
        override fun onTouchEvent(event: android.view.MotionEvent?): Boolean = false
    }.apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        setBackgroundColor(Color.BLACK)
        isClickable = false
        isFocusable = false
    }

    private val playerView: PlayerView = PlayerView(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        useController = false
        keepScreenOn = true
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        setShutterBackgroundColor(Color.BLACK)
        player = TubeShortsPlayerBridge.instance?.player
        isClickable = false
        isFocusable = false
        setOnTouchListener { _, _ -> false }
    }

    init {
        container.addView(playerView)
    }

    override fun getView(): View = container

    override fun dispose() {
        playerView.player = null
        container.removeAllViews()
    }
}

class TubeShortsPlayerViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        return TubeShortsPlatformView(context, viewId, creationParams)
    }
}
