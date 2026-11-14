package cn.local.imagebridge

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.view.Surface
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.annotations.ReactProp
import java.io.File
import java.lang.ref.WeakReference
import java.util.concurrent.Executors

class CameraSurface(private val react: ThemedReactContext) : FrameLayout(react) {
    companion object {
        var current = WeakReference<CameraSurface>(null)
        private val worker = Executors.newSingleThreadExecutor()
    }
    private val preview = PreviewView(react)
    private var provider: ProcessCameraProvider? = null
    private var photo: ImageCapture? = null
    private var video: VideoCapture<Recorder>? = null
    private var recording: Recording? = null
    private var requested = false
    private var generation = 0
    private var pendingRecord: Promise? = null
    init {
        setBackgroundColor(Color.BLACK)
        preview.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        preview.scaleType = PreviewView.ScaleType.FIT_CENTER
        addView(preview, LayoutParams(-1, -1))
    }
    private fun event(ready: Boolean, error: String = "") {
        val data = Arguments.createMap().apply {putBoolean("ready", ready); putString("error", error)}
        react.getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java).emit("ImageBridgeCamera", data)
    }
    fun activate(value: Boolean) {
        requested = value
        if (!value) {
            generation++; recording?.stop(); recording = null
            pendingRecord?.reject("VIDEO", "录像已取消"); pendingRecord = null
            provider?.unbindAll(); photo = null; video = null; event(false); return
        }
        if (!isAttachedToWindow) return
        if (ContextCompat.checkSelfPermission(react, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return
        bind(false)
    }
    private fun bind(forVideo: Boolean, then: (() -> Unit)? = null) {
        val owner = react.currentActivity as? LifecycleOwner ?: return
        val ticket = ++generation
        val future = ProcessCameraProvider.getInstance(react)
        future.addListener({
            if (!requested || ticket != generation) return@addListener
            try {
                val camera = future.get(); provider = camera; camera.unbindAll()
                val live = Preview.Builder().build().apply {surfaceProvider = preview.surfaceProvider}
                if (forVideo) {
                    val capture = VideoCapture.withOutput(Recorder.Builder().setQualitySelector(QualitySelector.from(Quality.HD)).build())
                    capture.targetRotation = display?.rotation ?: Surface.ROTATION_0
                    camera.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, live, capture); video = capture; photo = null
                } else {
                    val capture = ImageCapture.Builder().setJpegQuality(95).setTargetRotation(display?.rotation ?: Surface.ROTATION_0).build()
                    camera.bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, live, capture); photo = capture; video = null
                }
                event(true); then?.invoke()
            } catch (exception: Exception) {
                event(false, "无法打开相机：${exception.localizedMessage}")
                pendingRecord?.reject("CAMERA", exception.message, exception); pendingRecord = null
            }
        }, ContextCompat.getMainExecutor(react))
    }
    fun takePhoto(promise: Promise) {
        val capture = photo ?: run {promise.reject("CAMERA", "相机正在准备，请稍后再拍"); return}
        val file = newFile("jpg")
        capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(react), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: ImageCapture.OutputFileResults) {prepare(file, promise)}
            override fun onError(exception: ImageCaptureException) {Outbox.discard(react.cacheDir, file); promise.reject("CAMERA", "拍照失败，请重试", exception)}
        })
    }
    private var releaseRequested = false
    fun record(promise: Promise) {
        if (recording != null) {promise.reject("BUSY", "正在录像"); return}
        releaseRequested = false
        pendingRecord = promise
        bind(true) {
            pendingRecord = null
            if (releaseRequested) {promise.resolve(null); bind(false); return@bind}
            startRecording(promise)
        }
    }
    @android.annotation.SuppressLint("MissingPermission")
    private fun startRecording(promise: Promise) {
        val file = newFile("mp4")
        val output = FileOutputOptions.Builder(file).setFileSizeLimit(99900000).setDurationLimitMillis(30000).build()
        try {
            var pending = video!!.output.prepareRecording(react, output)
            if (ContextCompat.checkSelfPermission(react, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) pending = pending.withAudioEnabled()
            recording = pending.start(ContextCompat.getMainExecutor(react)) { result ->
                if (result is VideoRecordEvent.Finalize) {
                    recording = null
                    val valid = !result.hasError() || result.error == VideoRecordEvent.Finalize.ERROR_DURATION_LIMIT_REACHED || result.error == VideoRecordEvent.Finalize.ERROR_FILE_SIZE_LIMIT_REACHED
                    if (valid && file.length() > 0) prepare(file, promise)
                    else {file.delete(); promise.reject("VIDEO", "录像时间太短或保存失败，请重试")}
                    if (requested) bind(false)
                }
            }
        } catch (exception: Exception) {Outbox.discard(react.cacheDir, file); promise.reject("VIDEO", "无法开始录像，请检查麦克风权限", exception); bind(false)}
    }
    fun stopRecording() {releaseRequested = true; recording?.stop()}
    private fun newFile(extension: String): File = Outbox.create(react.cacheDir, extension)
    private fun prepare(file: File, promise: Promise) {
        worker.execute {try {promise.resolve(SharedInbox.prepare(react, file))} catch (exception: Exception) {promise.reject("MEDIA", exception.message, exception)}}
    }
    override fun onAttachedToWindow() {super.onAttachedToWindow(); current = WeakReference(this); if (requested) activate(true)}
    // React Native lays out the host view; the nested preview still needs Android measurement.
    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        preview.measure(MeasureSpec.makeMeasureSpec(right - left, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(bottom - top, MeasureSpec.EXACTLY))
        preview.layout(0, 0, right - left, bottom - top)
    }
    override fun requestLayout() {
        super.requestLayout()
        post {if (width > 0 && height > 0) {measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY)); layout(left, top, right, bottom)}}
    }
    override fun onDetachedFromWindow() {activate(false); if (current.get() === this) current.clear(); super.onDetachedFromWindow()}
}

class CameraSurfaceManager : SimpleViewManager<CameraSurface>() {
    override fun getName() = "ImageBridgeCameraView"
    override fun createViewInstance(context: ThemedReactContext) = CameraSurface(context)
    @ReactProp(name = "active") fun setActive(view: CameraSurface, value: Boolean) {view.activate(value)}
}
