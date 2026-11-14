package cn.local.imagebridge

import android.content.Context
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast

internal class RecordingPanel(context: Context, private val manager: WindowManager, onStop: () -> Unit) {
    private val density = context.resources.displayMetrics.density
    private fun dp(value: Int) = (value * density).toInt()
    private val timer = TextView(context).apply {
        text = "● 录屏 00:00 / 30\n按住拖动"
        textSize = 12f; setTextColor(Color.WHITE); gravity = Gravity.CENTER_VERTICAL
        contentDescription = "录屏计时，按住可拖动"
    }
    private val stop = Button(context).apply {
        text = "■ 停止"; textSize = 13f; isAllCaps = false; setTextColor(Color.WHITE)
        minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0
        setPadding(dp(4), 0, dp(4), 0)
        background = GradientDrawable().apply {setColor(Color.rgb(194, 48, 56)); cornerRadius = dp(16).toFloat()}
        contentDescription = "停止录屏并预览"; setOnClickListener {onStop()}
    }
    private val root = LinearLayout(context).apply {
        gravity = Gravity.CENTER_VERTICAL; setPadding(dp(12), dp(8), dp(8), dp(8))
        background = GradientDrawable().apply {setColor(Color.rgb(37, 26, 30)); cornerRadius = dp(24).toFloat()}
        addView(timer, LinearLayout.LayoutParams(0, dp(44), 1f))
        addView(stop, LinearLayout.LayoutParams(dp(66), dp(44)).apply {marginStart = dp(6)})
    }
    private val params = WindowManager.LayoutParams(dp(214), dp(60), WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT).apply {
        gravity = Gravity.TOP or Gravity.START
        x = (context.resources.displayMetrics.widthPixels - dp(222)).coerceAtLeast(0); y = dp(64)
    }
    private var closed = false

    init {
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var moved = false
        timer.setOnClickListener {Toast.makeText(context, "点右侧「停止」结束录屏；按住计时可拖动", Toast.LENGTH_SHORT).show()}
        timer.setOnTouchListener {view, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {downX = event.rawX; downY = event.rawY; startX = params.x; startY = params.y; moved = false}
                MotionEvent.ACTION_MOVE -> {
                    moved = moved || kotlin.math.abs(event.rawX - downX) + kotlin.math.abs(event.rawY - downY) > dp(8)
                    val metrics = context.resources.displayMetrics
                    params.x = (startX + event.rawX - downX).toInt().coerceIn(0, (metrics.widthPixels - root.width).coerceAtLeast(0))
                    params.y = (startY + event.rawY - downY).toInt().coerceIn(0, (metrics.heightPixels - root.height).coerceAtLeast(0))
                    manager.updateViewLayout(root, params)
                }
                MotionEvent.ACTION_UP -> if (!moved) view.performClick()
            }
            true
        }
        manager.addView(root, params)
    }
    fun update(seconds: Long) {if (!closed) timer.text = "● 录屏 00:${seconds.coerceIn(0, 30).toString().padStart(2, '0')} / 30\n按住拖动"}
    fun finishing() {if (!closed) {timer.text = "录屏已结束\n正在生成预览…"; stop.isEnabled = false; stop.alpha = .5f}}
    fun close() {if (!closed) {closed = true; manager.removeView(root)}}
}
