package cn.local.imagebridge

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import android.view.Surface
import java.io.File

class ScreenRecorder(private val context: Context, screenWidth: Int, screenHeight: Int, onLimit: () -> Unit) {
    val file: File = Outbox.create(context.cacheDir, "mp4")
    // MIUI can retain the original projection viewport when switching surfaces;
    // a smaller encoder surface then records only the top-left part of the screen.
    val width = screenWidth
    val height = screenHeight
    private val recorder = if (Build.VERSION.SDK_INT >= 31) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
    private var started = false
    private var outputSurface: Surface? = null
    val surface: Surface get() = requireNotNull(outputSurface)

    init {
        try {
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            recorder.setVideoSize(width, height)
            recorder.setVideoFrameRate(30)
            recorder.setVideoEncodingBitRate(8000000)
            recorder.setMaxDuration(30000)
            recorder.setMaxFileSize(99900000)
            recorder.setOutputFile(file.absolutePath)
            recorder.setOnInfoListener {_, what, _ ->
                if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED || what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_FILESIZE_REACHED) onLimit()
            }
            recorder.setOnErrorListener {_, _, _ -> onLimit()}
            recorder.prepare()
            outputSurface = recorder.surface
        } catch (exception: Exception) {recorder.release(); Outbox.discard(context.cacheDir, file); throw exception}
    }
    fun start() {recorder.start(); started = true}
    fun finish(keep: Boolean): File? {
        var valid = keep && started
        try {if (started) recorder.stop()} catch (_: RuntimeException) {valid = false}
        finally {recorder.release(); outputSurface?.release(); outputSurface = null; started = false}
        if (!valid || file.length() == 0L) {Outbox.discard(context.cacheDir, file); return null}
        return file
    }
}
