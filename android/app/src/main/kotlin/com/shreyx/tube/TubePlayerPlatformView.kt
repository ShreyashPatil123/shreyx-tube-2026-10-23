package com.shreyx.tube

import android.content.Context
import android.graphics.Color
import android.view.View
import android.view.LayoutInflater
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * PlatformView embedding AndroidX Media3 PlayerView into Flutter.
 */
class TubePlayerPlatformView(
    context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?
) : PlatformView {
    companion object {
        private var active: TubePlayerPlatformView? = null
        fun attachActivePlayer() { active?.playerView?.player = TubePlayerBridge.instance?.player }
    }


    private val container: FrameLayout = FrameLayout(context).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        setBackgroundColor(Color.BLACK)
    }

    // TextureView stays inside Flutter's texture composition during resizing; a
    // SurfaceView forces virtual-display recreation and can flash or lose frames.
    private val playerView: PlayerView = (LayoutInflater.from(context)
        .inflate(R.layout.tube_player_surface, container, false) as PlayerView).apply {
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT
        )
        useController = false
        keepScreenOn = true
        setShutterBackgroundColor(Color.BLACK)
        setKeepContentOnPlayerReset(true)
    }

    init {
        // A single surface owns the service's player; late disposal cannot detach a newer view.
        val previous = active?.playerView
        active = this
        TubePlayerBridge.instance?.player?.let { PlayerView.switchTargetView(it, previous, playerView) }
        container.addView(playerView)
    }

    override fun getView(): View = container

    override fun dispose() {
        if (active === this) active = null
        playerView.player = null
        container.removeAllViews()
    }
}

class TubePlayerViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String?, Any?>
        return TubePlayerPlatformView(context, viewId, creationParams)
    }
}
