package cn.local.imagebridge

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.io.File
import java.util.UUID

class CameraActivity : AppCompatActivity() {
    private lateinit var preview: PreviewView
    private lateinit var shutter: Button
    private lateinit var message: TextView
    private var capture: ImageCapture? = null
    private var front = false
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        preview = PreviewView(this)
        root.addView(preview, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT))
        message = TextView(this).apply {text = "拍好后，确认发送到电脑"; setTextColor(Color.WHITE); textSize = 15f; gravity = Gravity.CENTER}
        root.addView(message, FrameLayout.LayoutParams(-1, dp(60), Gravity.TOP).apply {topMargin = dp(36)})
        shutter = Button(this).apply {text = "拍照"; textSize = 18f; setTextColor(Color.WHITE); backgroundTintList = android.content.res.ColorStateList.valueOf(Color.rgb(37, 99, 235)); setOnClickListener {takePhoto()} }
        root.addView(shutter, FrameLayout.LayoutParams(dp(116), dp(62), Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {bottomMargin = dp(54)})
        val back = Button(this).apply {text = "返回"; setOnClickListener {finish()} }
        root.addView(back, FrameLayout.LayoutParams(dp(80), dp(50), Gravity.BOTTOM or Gravity.START).apply {leftMargin = dp(18); bottomMargin = dp(60)})
        val flip = Button(this).apply {text = "翻转"; setOnClickListener {front = !front; startCamera()} }
        root.addView(flip, FrameLayout.LayoutParams(dp(80), dp(50), Gravity.BOTTOM or Gravity.END).apply {rightMargin = dp(18); bottomMargin = dp(60)})
        setContentView(root); startCamera()
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun startCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            try {
                val provider = future.get(); provider.unbindAll()
                val live = Preview.Builder().build().apply {surfaceProvider = preview.surfaceProvider}
                val imageCapture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).setJpegQuality(95).build()
                provider.bindToLifecycle(this, if (front) CameraSelector.DEFAULT_FRONT_CAMERA else CameraSelector.DEFAULT_BACK_CAMERA, live, imageCapture)
                capture = imageCapture; shutter.isEnabled = true
            } catch (exception: Exception) {message.text = "无法打开相机：${exception.localizedMessage}"; shutter.isEnabled = false}
        }, ContextCompat.getMainExecutor(this))
    }
    private fun takePhoto() {
        val camera = capture ?: return
        shutter.isEnabled = false
        val folder = File(cacheDir, "outbox").apply {mkdirs()}
        val photo = File(folder, UUID.randomUUID().toString() + ".jpg")
        camera.takePicture(ImageCapture.OutputFileOptions.Builder(photo).build(), ContextCompat.getMainExecutor(this), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                setResult(Activity.RESULT_OK, Intent().putExtra("imagePath", photo.path)); finish()
            }
            override fun onError(exception: ImageCaptureException) {message.text = "拍照失败，请重试"; shutter.isEnabled = true}
        })
    }
}
