package cn.local.imagebridge

import android.app.Activity
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import androidx.core.content.ContextCompat

class ScreenCaptureActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) {finish(); return}
        if (ScreenCaptureService.running) {Toast.makeText(this, "连续截屏已经开启", Toast.LENGTH_SHORT).show(); finish(); return}
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 3)
        } else requestOverlay()
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 3) requestOverlay()
    }
    private fun requestOverlay() {
        if (!Settings.canDrawOverlays(this)) {
            Toast.makeText(this, "请允许 CtrlC 显示悬浮按钮", Toast.LENGTH_LONG).show()
            startActivityForResult(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")), 1)
        } else requestCapture()
    }
    private fun requestCapture() {
        val manager = getSystemService(MediaProjectionManager::class.java)
        startActivityForResult(manager.createScreenCaptureIntent(), 2)
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1) {
            if (Settings.canDrawOverlays(this)) requestCapture()
            else {Toast.makeText(this, "未允许悬浮窗，连续截屏未开启", Toast.LENGTH_LONG).show(); finish()}
            return
        }
        if (requestCode != 2) return
        if (resultCode == RESULT_OK && data != null) {
            ContextCompat.startForegroundService(this, Intent(this, ScreenCaptureService::class.java).putExtra("resultCode", resultCode).putExtra("data", data))
            moveTaskToBack(true)
        } else Toast.makeText(this, "未授权屏幕采集", Toast.LENGTH_SHORT).show()
        finish()
    }
}
