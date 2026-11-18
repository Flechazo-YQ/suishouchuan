package cn.local.imagebridge

import android.app.Notification
import android.app.AlertDialog
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.Image
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.view.WindowManager
import android.widget.Toast
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class ScreenCaptureService : Service() {
    companion object {@Volatile var running = false}
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val collected = mutableListOf<JSONObject>()
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var reader: ImageReader? = null
    private val captureFrames = CaptureFrames<Image>()
    private var panel: CapturePanel? = null
    private var recordingPanel: RecordingPanel? = null
    private var screenRecorder: ScreenRecorder? = null
    private var recordStarting = false
    private var recordFinishing = false
    private var recordStarted = 0L
    private lateinit var manager: WindowManager
    private var capturePending = false
    private var readyToRead = false
    private var stopping = false
    private var generation = 0
    private var width = 0
    private var height = 0

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onCreate() {
        super.onCreate()
        manager = getSystemService(WindowManager::class.java)
        getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel("capture", "连续截屏", NotificationManager.IMPORTANCE_LOW))
        startForeground(7, notification())
    }
    private fun notification(): Notification {
        val stop = PendingIntent.getService(this, 7, Intent(this, ScreenCaptureService::class.java).setAction("STOP"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val recording = screenRecorder != null
        val seconds = ((SystemClock.elapsedRealtime() - recordStarted) / 1000).coerceIn(0, 30)
        return Notification.Builder(this, "capture").setSmallIcon(android.R.drawable.ic_menu_camera).setContentTitle(if (recording) "CtrlC · 录屏 ${seconds}s / 30s" else "CtrlC · 连续截屏")
            .setContentText(if (recording) "点悬浮「停止」可结束 · 完成后先预览" else "已截 ${collected.size} 张 · 点悬浮「截一张」，查看后确认发送")
            .setContentIntent(stop).setOngoing(true).addAction(Notification.Action.Builder(null, "结束并预览", stop).build()).build()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            if (recordStarting) {stopping = true; stopSelf()}
            else if (screenRecorder != null) finishRecording(true) else deliver(false, true)
            return START_NOT_STICKY
        }
        if (running) return START_NOT_STICKY
        try {
            val data = if (Build.VERSION.SDK_INT >= 33) intent?.getParcelableExtra("data", Intent::class.java)
                else @Suppress("DEPRECATION") intent?.getParcelableExtra<Intent>("data")
            requireNotNull(data) {"屏幕授权已失效，请重新开启"}
            projection = getSystemService(MediaProjectionManager::class.java).getMediaProjection(intent?.getIntExtra("resultCode", 0) ?: 0, data)
            projection!!.registerCallback(object : MediaProjection.Callback() {
                override fun onStop() {if (!stopping) {if (screenRecorder != null) finishRecording(false) else deliver(false, false)}}
                override fun onCapturedContentResize(w: Int, h: Int) {
                    if (!stopping && w > 0 && h > 0 && (w != width || h != height)) {
                        if (screenRecorder == null) resize(w, h)
                        else if (kotlin.math.abs(w.toDouble() / h - width.toDouble() / height) > .1) {toast("屏幕方向已改变，录屏已结束，请预览后发送"); finishRecording(true)}
                    }
                }
            }, handler)
            val dimensions = dimensions(); resize(dimensions.first, dimensions.second)
            showPanel(); running = true
        } catch (exception: Exception) {toast(exception.message ?: "无法开启连续截屏"); stopSelf()}
        return START_NOT_STICKY
    }
    private fun dimensions(): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= 30) return manager.maximumWindowMetrics.bounds.let {Pair(it.width(), it.height())}
        val metrics = android.util.DisplayMetrics()
        @Suppress("DEPRECATION") manager.defaultDisplay.getRealMetrics(metrics)
        return Pair(metrics.widthPixels, metrics.heightPixels)
    }
    private fun resize(w: Int, h: Int) {
        if (w.toLong() * h > 64000000) {toast("屏幕尺寸超过处理上限"); stopSelf(); return}
        if (capturePending) {generation++; restorePanel()}
        width = w; height = h
        val old = reader
        // One retained frame plus two free slots lets acquireLatestImage discard older frames.
        val next = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 3)
        reader = next
        next.setOnImageAvailableListener({source ->
            if (stopping || source !== reader) return@setOnImageAvailableListener
            source.acquireLatestImage()?.let {captureFrames.offer(it)}
            if (capturePending && readyToRead) readFrame()
        }, handler)
        if (display == null) display = projection!!.createVirtualDisplay("ImageBridge", w, h, resources.displayMetrics.densityDpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, next.surface, null, handler)
        else {display!!.resize(w, h, resources.displayMetrics.densityDpi); display!!.surface = next.surface}
        old?.close()
    }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (Build.VERSION.SDK_INT < 34 && projection != null && !stopping) {
            val dimensions = dimensions()
            if (screenRecorder != null && (dimensions.first != width || dimensions.second != height)) {toast("屏幕方向已改变，录屏已结束"); finishRecording(true)}
            else if (screenRecorder == null) resize(dimensions.first, dimensions.second)
        }
    }
    private fun showPanel() {
        panel = CapturePanel(this, manager, {capture()}, {confirmRecording()}, {deliver(false, true)}, {
            if (collected.isEmpty()) stopSelf() else deliver(false, true)
        })
    }
    private fun confirmRecording() {
        if (collected.isNotEmpty()) {toast("先点「查看图片」确认这一组，再开启录屏"); return}
        val dialog = AlertDialog.Builder(this).setTitle("无声录屏 · 最长 30 秒")
            .setMessage("录制时显示计时和「停止」浮窗，点停止可随时结束，30 秒自动停止。\n\n计时浮窗也会出现在视频里，可按住拖到角落。完成后先预览，确认后才发送。")
            .setNegativeButton("取消", null).setPositiveButton("开始录屏") {_, _ -> startRecording()}.create()
        dialog.window?.setType(WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY)
        dialog.show()
    }
    private fun capture() {
        if (capturePending || stopping || screenRecorder != null || recordStarting) return
        if (collected.size >= 10) {toast("已收集 10 张，请点「查看图片」确认发送"); return}
        reader?.acquireLatestImage()?.close()
        capturePending = true; readyToRead = false; val ticket = ++generation
        captureFrames.begin()
        panel?.hide()
        // Allow the compositor to render a frame after hiding our own overlay.
        handler.postDelayed({if (!stopping && ticket == generation) {readyToRead = true; readFrame()}}, 250)
        handler.postDelayed({if (capturePending && readyToRead && ticket == generation) {restorePanel(); toast("未取得屏幕画面，请重试")}}, 2500)
    }
    private fun readFrame() {
        reader?.acquireLatestImage()?.let {captureFrames.offer(it)}
        val frame = captureFrames.take() ?: return
        readyToRead = false
        val bitmap: Bitmap
        try {
            val plane = frame.planes[0]
            val padded = Bitmap.createBitmap(plane.rowStride / plane.pixelStride, frame.height, Bitmap.Config.ARGB_8888)
            padded.copyPixelsFromBuffer(plane.buffer)
            bitmap = Bitmap.createBitmap(padded, 0, 0, frame.width, frame.height)
            if (bitmap !== padded) padded.recycle()
        } catch (exception: Exception) {restorePanel(); toast("屏幕画面读取失败"); return}
        finally {frame.close()}
        worker.execute {
            val file = Outbox.create(cacheDir, "png")
            try {
                file.outputStream().use {check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) {"截屏保存失败"}}
                val image = JSONObject(SharedInbox.prepare(this, file))
                handler.post {
                    if (stopping || collected.sumOf {it.getLong("bytes")} + file.length() > 100000000L) {Outbox.discard(cacheDir, file); if (!stopping) toast("整组超过 100 MB，请先发送现有截图")}
                    else {collected.add(image); startForeground(7, notification()); panel?.captured(collected.size, file)}
                    restorePanel()
                }
            } catch (exception: Exception) {Outbox.discard(cacheDir, file); handler.post {restorePanel(); toast(exception.message ?: "截屏失败")}}
            finally {bitmap.recycle()}
        }
    }
    private fun restorePanel() {
        capturePending = false; readyToRead = false
        captureFrames.cancel()
        if (stopping) return
        panel?.show()
    }
    private fun startRecording() {
        if (capturePending || recordStarting || stopping || screenRecorder != null) return
        if (collected.isNotEmpty()) {toast("先点「查看图片」确认这一组，再开启录屏"); return}
        recordStarting = true; panel?.hide()
        handler.postDelayed({
            if (stopping) return@postDelayed
            try {
                val recorder = ScreenRecorder(this, width, height) {handler.post {finishRecording(true)}}
                screenRecorder = recorder
                display?.surface = null
                display?.surface = recorder.surface
                recorder.start(); recordStarted = SystemClock.elapsedRealtime(); recordStarting = false
                recordingPanel = RecordingPanel(this, manager) {finishRecording(true)}
                updateRecordingNotification()
                handler.postDelayed({finishRecording(true)}, 30000)
            } catch (exception: Exception) {
                screenRecorder?.finish(false); screenRecorder = null; recordStarting = false
                toast(exception.message ?: "录屏无法开始，请重试"); stopSelf()
            }
        }, 500)
    }
    private fun updateRecordingNotification() {
        if (screenRecorder == null || stopping) return
        recordingPanel?.update((SystemClock.elapsedRealtime() - recordStarted) / 1000)
        startForeground(7, notification())
        handler.postDelayed({updateRecordingNotification()}, 1000)
    }
    private fun finishRecording(open: Boolean) {
        val recorder = screenRecorder ?: return
        if (recordFinishing) return
        recordFinishing = true; stopping = true; screenRecorder = null; display?.surface = null
        recordingPanel?.finishing()
        val file = recorder.finish(true)
        if (file == null) {recordingFailed("录屏太短或保存失败，请重试"); return}
        worker.execute {
            try {
                val bounded = ScreenRecordingLimit.apply(cacheDir, file)
                SharedInbox.publish(this, SharedInbox.prepare(this, bounded))
                handler.post {if (open) openPreview(); stopSelf()}
            } catch (exception: Exception) {
                android.util.Log.w("ImageBridgeCapture", "Unable to prepare completed recording", exception)
                Outbox.discard(cacheDir, file)
                handler.post {recordingFailed(exception.message ?: "录屏保存失败")}
            }
        }
    }
    private fun recordingFailed(message: String) {
        // A transient toast is easy to miss when recording ends in another app.
        SharedInbox.error = message
        toast(message)
        stopSelf()
    }
    private fun openPreview() {startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))}
    private fun deliver(autoSend: Boolean, open: Boolean) {
        if (capturePending && open) {toast("正在处理截图，请稍候"); return}
        if (collected.isNotEmpty()) {
            SharedInbox.publish(this, SharedInbox.batch(JSONArray(collected), autoSend))
            collected.clear()
            if (open) openPreview()
        } else if (open) {toast("请先截取至少一张图片"); return}
        stopSelf()
    }
    private fun toast(message: String) {Toast.makeText(this, message, Toast.LENGTH_LONG).show()}
    override fun onDestroy() {
        stopping = true; running = false; generation++; handler.removeCallbacksAndMessages(null)
        captureFrames.cancel()
        panel?.close(); panel = null
        recordingPanel?.close(); recordingPanel = null
        screenRecorder?.finish(false); screenRecorder = null
        display?.release(); reader?.setOnImageAvailableListener(null, null); reader?.close(); projection?.stop()
        collected.forEach {Outbox.discard(cacheDir, File(it.getString("path")))}; collected.clear()
        worker.shutdown(); super.onDestroy()
    }
}
