package cn.local.imagebridge

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import java.io.File

class CapturePanel(private val context: Context, private val manager: WindowManager,
    onCapture: () -> Unit, onRecord: () -> Unit, onReview: () -> Unit, onClose: () -> Unit) {
    private val root = LinearLayout(context).apply {orientation = LinearLayout.VERTICAL; setPadding(dp(12), dp(4), dp(8), dp(12)); background = shape("#171D24", 20)}
    private val params = WindowManager.LayoutParams(dp(264), -2, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT).apply {gravity = Gravity.TOP or Gravity.START; x = dp(8); y = dp(140)}
    private val hint = TextView(context).apply {text = "点「截一张」收集 · 最多 10 张"; textSize = 11f; setTextColor(Color.LTGRAY); setPadding(dp(4), 0, 0, dp(10))}
    private val review = button("暂无截图", "#303A46", onReview)
    private val thumbnail = ImageView(context).apply {scaleType = ImageView.ScaleType.CENTER_CROP; contentDescription = "最近一次截图"}
    private var bitmap: Bitmap? = null
    private var flash: View? = null
    private var closed = false

    init {
        val top = LinearLayout(context).apply {gravity = Gravity.CENTER_VERTICAL}
        val drag = TextView(context).apply {text = "按住拖动"; textSize = 12f; setTextColor(Color.LTGRAY); gravity = Gravity.CENTER_VERTICAL; contentDescription = "按住并拖动，移动截屏工具栏"}
        top.addView(drag, LinearLayout.LayoutParams(0, dp(40), 1f))
        top.addView(button("×", "#171D24", onClose).apply {textSize = 24f; contentDescription = "关闭采集并查看已有截图"}, LinearLayout.LayoutParams(dp(40), dp(40)))
        var downX = 0f; var downY = 0f; var startX = 0; var startY = 0; var moved = false
        drag.setOnClickListener {Toast.makeText(context, "按住这行文字并拖动，可移动工具栏", Toast.LENGTH_SHORT).show()}
        drag.setOnTouchListener {view, event ->
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
        root.addView(top); root.addView(hint)
        val actions = LinearLayout(context)
        actions.addView(button("截一张", "#D9F278", onCapture).apply {setTextColor(Color.rgb(24, 31, 22))}, LinearLayout.LayoutParams(0, dp(48), 1f).apply {marginEnd = dp(8)})
        actions.addView(button("录屏", "#303A46", onRecord), LinearLayout.LayoutParams(0, dp(48), 1f))
        root.addView(actions)
        val footer = LinearLayout(context).apply {gravity = Gravity.CENTER_VERTICAL; setPadding(0, dp(10), 0, 0)}
        footer.addView(thumbnail, LinearLayout.LayoutParams(dp(38), dp(38)).apply {marginEnd = dp(8)})
        footer.addView(review, LinearLayout.LayoutParams(0, dp(40), 1f)); root.addView(footer)
        review.isEnabled = false; review.alpha = .45f
        manager.addView(root, params)
    }
    private fun dp(value: Int) = (value * context.resources.displayMetrics.density).toInt()
    private fun shape(color: String, radius: Int) = GradientDrawable().apply {setColor(Color.parseColor(color)); cornerRadius = dp(radius).toFloat()}
    private fun button(label: String, color: String, action: () -> Unit) = Button(context).apply {
        text = label; textSize = 14f; minWidth = 0; minimumWidth = 0; minHeight = 0; minimumHeight = 0; isAllCaps = false
        setTextColor(Color.WHITE); background = shape(color, 12); setPadding(dp(6), 0, dp(6), 0); setOnClickListener {action()}
    }
    fun hide() {removeFlash(); root.visibility = View.INVISIBLE}
    fun show() {if (!closed) root.visibility = View.VISIBLE}
    fun captured(count: Int, file: File) {
        if (closed) return
        thumbnail.setImageDrawable(null); bitmap?.recycle(); bitmap = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply {inSampleSize = 8}); thumbnail.setImageBitmap(bitmap)
        hint.text = "已截好 $count 张 · 查看后再确认发送"
        review.text = "查看图片 ($count)"; review.isEnabled = true; review.alpha = 1f
        show()
        val view = View(context).apply {setBackgroundColor(Color.WHITE); alpha = .22f}
        val flashParams = WindowManager.LayoutParams(-1, -1, WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN, PixelFormat.TRANSLUCENT)
        flash = view; manager.addView(view, flashParams)
        view.animate().alpha(0f).setDuration(180).withEndAction {removeFlash()}.start()
    }
    private fun removeFlash() {flash?.let {it.animate().cancel(); manager.removeView(it)}; flash = null}
    fun close() {if (closed) return; closed = true; removeFlash(); manager.removeView(root); thumbnail.setImageDrawable(null); bitmap?.recycle(); bitmap = null}
}
