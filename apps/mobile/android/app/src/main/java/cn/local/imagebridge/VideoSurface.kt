package cn.local.imagebridge

import android.content.Context
import android.widget.FrameLayout
import android.widget.VideoView
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.io.File

class VideoSurface(context: Context) : FrameLayout(context) {
    private val video = VideoView(context)
    private var sourceWidth = 0
    private var sourceHeight = 0

    init {
        addView(video, LayoutParams(-1, -1))
        video.setOnPreparedListener { player ->
            sourceWidth = player.videoWidth
            sourceHeight = player.videoHeight
            layoutVideo()
            player.isLooping = true
            player.setVolume(0f, 0f)
            video.start()
        }
    }

    fun setPath(path: String) = video.setVideoPath(path)
    fun stop() = video.stopPlayback()

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        layoutVideo()
    }

    override fun requestLayout() {
        super.requestLayout()
        post { if (width > 0 && height > 0) layoutVideo() }
    }

    private fun layoutVideo() {
        // React Native gives its direct child exact bounds; keep aspect fitting inside a native wrapper.
        // VideoView needs a nonempty Surface before it can prepare and report the source size.
        val bounds = if (sourceWidth > 0 && sourceHeight > 0) fitVideoBounds(width, height, sourceWidth, sourceHeight)
            else VideoBounds(width, height)
        video.measure(MeasureSpec.makeMeasureSpec(bounds.width, MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(bounds.height, MeasureSpec.EXACTLY))
        val left = (width - bounds.width) / 2
        val top = (height - bounds.height) / 2
        video.layout(left, top, left + bounds.width, top + bounds.height)
    }
}

class VideoSurfaceManager : SimpleViewManager<VideoSurface>() {
    override fun getName() = "ImageBridgeVideoView"
    override fun createViewInstance(context: ThemedReactContext) = VideoSurface(context)
    @ReactProp(name = "path") fun setPath(view: VideoSurface, path: String?) {
        if (path == null) return
        val file = File(path)
        require(file.canonicalPath.startsWith(view.context.cacheDir.canonicalPath + File.separator))
        view.setPath(file.path)
    }
    override fun onDropViewInstance(view: VideoSurface) {view.stop(); super.onDropViewInstance(view)}
}
