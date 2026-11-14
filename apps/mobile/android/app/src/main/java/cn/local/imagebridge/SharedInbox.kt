package cn.local.imagebridge

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

object SharedInbox {
    private val executor = Executors.newSingleThreadExecutor()
    private val pending = AtomicReference<String?>(null)
    fun takePending(): String? = pending.getAndSet(null)
    @Volatile var error: String? = null
    @Volatile var pairingUri: String? = null
    private const val LIMIT = 32L * 1024 * 1024

    fun accept(context: Context, intent: Intent?) {
        if (intent?.action == Intent.ACTION_VIEW && intent.data?.scheme == "imagebridge" && intent.data?.host == "pair") {
            pairingUri = intent.data.toString(); intent.action = null; return
        }
        if (intent?.action == Intent.ACTION_SEND_MULTIPLE) {
            val uris = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
                else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            intent.action = null
            acceptMany(context, uris ?: emptyList()); return
        }
        if (intent?.action != Intent.ACTION_SEND) return
        val uri = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
            else @Suppress("DEPRECATION") intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        if (uri == null) { error = "没有收到图片，请从截图或相册重新分享"; return }
        intent.action = null
        executor.execute {
            val file = Outbox.create(context.cacheDir, "source")
            try {
                context.contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "无法读取共享图片" }
                    file.outputStream().use { output ->
                        val buffer = ByteArray(65536); var total = 0L
                        var count = input.read(buffer)
                        while (count != -1) {
                            total += count
                            require(total <= LIMIT) { "图片上限为 32 MB" }
                            output.write(buffer, 0, count); count = input.read(buffer)
                        }
                    }
                }
                val prepared = prepare(context, file)
                publish(context, prepared)
                error = null
            } catch (exception: Exception) {Outbox.discard(context.cacheDir, file); error = exception.message ?: "图片读取失败，请重试" }
        }
    }

    fun discardPayload(context: Context, payload: String) {
        val value = JSONObject(payload)
        val images = value.optJSONArray("images") ?: JSONArray().put(value)
        for (index in 0 until images.length()) Outbox.discard(context.cacheDir, File(images.getJSONObject(index).getString("path")))
    }
    fun publish(context: Context, payload: String) {
        pending.getAndSet(payload)?.let {discardPayload(context, it)}
        error = null
    }
    fun batch(images: JSONArray, autoSend: Boolean = true): String {
        require(images.length() in 1..10) {"每组请选择 1–10 张图片"}
        val total = (0 until images.length()).sumOf {images.getJSONObject(it).getLong("bytes")}
        require(total <= 100000000L) {"整组超过 100 MB，请分成更小的图集"}
        return JSONObject().put("requestId", UUID.randomUUID().toString()).put("images", images).put("autoSend", autoSend).toString()
    }
    fun acceptMany(context: Context, uris: List<Uri>) {
        executor.execute {
            val images = JSONArray()
            try {
                require(uris.size in 1..10) {"每组请选择 1–10 张图片"}
                for (uri in uris) {
                    val file = Outbox.create(context.cacheDir, "source")
                    try {
                        context.contentResolver.openInputStream(uri).use {input ->
                            requireNotNull(input) {"无法读取共享图片"}
                            file.outputStream().use {output ->
                                val buffer = ByteArray(65536); var total = 0L; var count = input.read(buffer)
                                while (count != -1) {
                                    total += count; require(total <= LIMIT) {"图片上限为 32 MB"}
                                    output.write(buffer, 0, count); count = input.read(buffer)
                                }
                            }
                        }
                        images.put(JSONObject(prepare(context, file)))
                    } catch (exception: Exception) {Outbox.discard(context.cacheDir, file); throw exception}
                    require((0 until images.length()).sumOf {images.getJSONObject(it).getLong("bytes")} <= 100000000L) {"整组超过 100 MB，请拆分发送"}
                }
                publish(context, batch(images))
            } catch (exception: Exception) {
                for (index in 0 until images.length()) Outbox.discard(context.cacheDir, File(images.getJSONObject(index).getString("path")))
                error = exception.message ?: "读取图集失败，请重试"
            }
        }
    }

    fun prepare(context: Context, source: File): String {
        try {return prepareMedia(context, source)}
        catch (exception: Exception) {Outbox.discard(context.cacheDir, source); throw exception}
    }
    private fun prepareMedia(context: Context, source: File): String {
        require(source.canonicalPath.startsWith(context.cacheDir.canonicalPath + File.separator)) { "图片来源无效" }
        if (source.extension == "mp4") return prepareVideo(source)
        require(source.length() in 1..LIMIT) { "图片上限为 32 MB" }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.path, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0 && bounds.outWidth.toLong() * bounds.outHeight <= 64000000) { "仅支持 6400 万像素以内的静态图片" }
        var image = source
        var mime = bounds.outMimeType ?: ""
        if (mime != "image/png" && mime != "image/jpeg") {
            require(mime in listOf("image/heic", "image/heif", "image/avif")) { "仅支持静态 PNG、JPEG、HEIC 图片" }
            if (Build.VERSION.SDK_INT < 28) throw IllegalArgumentException("这台手机暂不支持该格式，请先转成 JPEG 或 PNG")
            val decoder = ImageDecoder.createSource(source)
            val bitmap = ImageDecoder.decodeBitmap(decoder) { settings, _, _ -> settings.allocator = ImageDecoder.ALLOCATOR_SOFTWARE }
            mime = if (bitmap.hasAlpha()) "image/png" else "image/jpeg"
            image = Outbox.create(context.cacheDir, if (mime == "image/png") "png" else "jpg")
            try {
                image.outputStream().use { output -> check(bitmap.compress(if (mime == "image/png") Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 95, output)) {"图片转换失败"} }
                require(image.length() <= LIMIT) { "转换后图片超过 32 MB，请选择较小的图片" }
            } catch (exception: Exception) {Outbox.discard(context.cacheDir, image); throw exception}
            finally {bitmap.recycle()}
            Outbox.discard(context.cacheDir, source)
        }
        require(image.length() <= LIMIT) { "转换后图片超过 32 MB，请选择较小的图片" }
        error = null
        return JSONObject().put("path", image.path).put("uri", Uri.fromFile(image).toString()).put("mime", mime)
            .put("bytes", image.length()).put("width", bounds.outWidth).put("height", bounds.outHeight).put("requestId", UUID.randomUUID().toString()).toString()
    }
    private fun prepareVideo(source: File): String {
        require(source.length() in 1..100000000L) { "视频上限为 100 MB" }
        val metadata = MediaMetadataRetriever()
        try {
            metadata.setDataSource(source.path)
            val duration = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            require(duration in 1..30100) { "视频最长 30 秒，本次文件时长 ${duration / 1000.0} 秒" }
            var width = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            var height = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            if (rotation == 90 || rotation == 270) {val previous = width; width = height; height = previous}
            error = null
            return JSONObject().put("path", source.path).put("uri", Uri.fromFile(source).toString()).put("mime", "video/mp4")
                .put("bytes", source.length()).put("width", width).put("height", height).put("durationMs", duration).put("requestId", UUID.randomUUID().toString()).toString()
        } finally {metadata.release()}
    }
}
