package cn.local.imagebridge

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.facebook.react.bridge.BaseActivityEventListener
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.google.zxing.integration.android.IntentIntegrator
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

class BridgeModule(private val context: ReactApplicationContext) : ReactContextBaseJavaModule(context) {
    private val storage = SecureStore(context)
    private val discovery = Discovery(context)
    private val executor = Executors.newSingleThreadExecutor()
    private var activityPromise: Promise? = null
    init {
        storage.write(storage.read())
        context.addActivityEventListener(object : BaseActivityEventListener() {
            override fun onActivityResult(activity: Activity, request: Int, result: Int, data: Intent?) {
                if (request == 4713) {
                    if (result == Activity.RESULT_OK && data != null) {
                        val uris = data.clipData?.let {clip -> (0 until clip.itemCount).map {clip.getItemAt(it).uri}} ?: listOfNotNull(data.data)
                        SharedInbox.acceptMany(context, uris)
                    }
                    return
                }
                if (request != 4711 && request != 4712) return
                val promise = activityPromise ?: return
                activityPromise = null
                if (result != Activity.RESULT_OK) {promise.resolve(null); return}
                if (request == 4711) {promise.resolve(data?.getStringExtra("SCAN_RESULT")); return}
                val filename = data?.getStringExtra("imagePath") ?: run {promise.reject("CAMERA", "拍照结果为空，请重试"); return}
                work(promise) {SharedInbox.prepare(context, File(filename))}
            }
        })
    }
    override fun getName() = "ImageBridge"
    private fun work(promise: Promise, action: () -> String) {
        executor.execute {try {promise.resolve(action())} catch (exception: Exception) {promise.reject("BRIDGE", exception.message ?: "操作失败，请重试", exception)}}
    }
    @ReactMethod fun getState(promise: Promise) = work(promise) {
        val data = storage.read(); val devices = data.getJSONArray("devices"); val publicDevices = JSONArray()
        for (index in 0 until devices.length()) {
            val device = JSONObject(devices.getJSONObject(index).toString()); device.remove("token"); publicDevices.put(device)
        }
        JSONObject().put("devices", publicDevices).put("defaultId", data.optString("defaultId"))
            .put("discovered", discovery.list()).put("sharedError", SharedInbox.error ?: "").toString()
    }
    @ReactMethod fun takePending(promise: Promise) {promise.resolve(SharedInbox.takePending())}
    @ReactMethod fun takePairing(promise: Promise) {val pending = SharedInbox.pairingUri; SharedInbox.pairingUri = null; promise.resolve(pending)}
    @ReactMethod fun discover(promise: Promise) {try {discovery.start(); promise.resolve(null)} catch (exception: Exception) {promise.reject("DISCOVERY", exception.message, exception)}}
    @ReactMethod fun stopDiscovery() {discovery.stop()}
    @ReactMethod fun selectDevice(id: String, promise: Promise) = work(promise) {
        val data = storage.read(); val devices = data.getJSONArray("devices")
        require((0 until devices.length()).any { devices.getJSONObject(it).optString("deviceId") == id }) { "设备不存在" }
        data.put("defaultId", id); storage.write(data); "{}"
    }
    @ReactMethod fun removeDevice(id: String, promise: Promise) = work(promise) {
        val data = storage.read(); val devices = data.getJSONArray("devices"); val remaining = JSONArray()
        for (index in 0 until devices.length()) if (devices.getJSONObject(index).optString("deviceId") != id) remaining.put(devices.getJSONObject(index))
        data.put("devices", remaining)
        if (data.optString("defaultId") == id) data.put("defaultId", if (remaining.length() > 0) remaining.getJSONObject(0).getString("deviceId") else "")
        storage.write(data); "{}"
    }
    @ReactMethod fun pair(uriText: String, promise: Promise) = work(promise) {
        val uri = Uri.parse(uriText)
        require(uri.scheme == "imagebridge" && uri.host == "pair") { "请扫描随手传电脑端的配对二维码" }
        val invitation = JSONObject(uri.getQueryParameter("data") ?: "{}")
        require(invitation.getInt("v") == 1 && invitation.getLong("expiresAt") > System.currentTimeMillis()) { "二维码已过期，请在电脑端刷新" }
        val data = storage.read()
        val response = PinnedClient(invitation).request("/v1/pair", JSONObject().put("code", invitation.getString("code"))
            .put("clientId", data.getString("clientId")).put("name", Build.MODEL.take(80)))
        require(response.getString("deviceId") == invitation.getString("deviceId")) { "电脑身份不匹配" }
        invitation.remove("code"); invitation.remove("expiresAt")
        invitation.put("token", response.getString("token")).put("name", response.getString("name"))
        val devices = data.getJSONArray("devices"); val updated = JSONArray()
        for (index in 0 until devices.length()) if (devices.getJSONObject(index).optString("deviceId") != invitation.getString("deviceId")) updated.put(devices.getJSONObject(index))
        updated.put(invitation); data.put("devices", updated).put("defaultId", invitation.getString("deviceId")); storage.write(data)
        JSONObject().put("name", invitation.getString("name")).toString()
    }
    @ReactMethod fun scanQr(promise: Promise) {
        val activity = context.currentActivity ?: run {promise.reject("ACTIVITY", "请先打开应用"); return}
        if (activityPromise != null) {promise.reject("BUSY", "请先完成当前操作"); return}
        activityPromise = promise
        val intent = IntentIntegrator(activity).setDesiredBarcodeFormats(IntentIntegrator.QR_CODE).setPrompt("扫描电脑端的配对二维码")
            .setBeepEnabled(false).setOrientationLocked(false).createScanIntent()
        activity.startActivityForResult(intent, 4711)
    }
    @ReactMethod fun capture(promise: Promise) {
        context.runOnUiQueueThread {
            val camera = CameraSurface.current.get()
            if (camera == null) promise.reject("CAMERA", "相机正在准备，请稍后再拍") else camera.takePhoto(promise)
        }
    }
    @ReactMethod fun record(promise: Promise) {context.runOnUiQueueThread {
        val camera = CameraSurface.current.get()
        if (camera == null) promise.reject("CAMERA", "相机正在准备") else camera.record(promise)
    }}
    @ReactMethod fun stopRecording() {context.runOnUiQueueThread {CameraSurface.current.get()?.stopRecording()}}
    @ReactMethod fun pickImages(promise: Promise) {
        val activity = context.currentActivity ?: run {promise.reject("ACTIVITY", "请先打开应用"); return}
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {type = "image/*"; addCategory(Intent.CATEGORY_OPENABLE); putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)}
        try {activity.startActivityForResult(intent, 4713); promise.resolve(null)} catch (exception: Exception) {promise.reject("PICKER", exception.message, exception)}
    }
    @ReactMethod fun startScreenCapture(promise: Promise) {
        val activity = context.currentActivity ?: run {promise.reject("ACTIVITY", "请先打开应用"); return}
        try {activity.startActivity(Intent(activity, ScreenCaptureActivity::class.java)); promise.resolve(null)}
        catch (exception: Exception) {promise.reject("CAPTURE", exception.message, exception)}
    }
    @ReactMethod fun createBatch(images: String, promise: Promise) = work(promise) {SharedInbox.batch(JSONArray(images), false)}
    @ReactMethod fun sendBatch(deviceId: String, payload: String, promise: Promise) = work(promise) {
        val started = android.os.SystemClock.elapsedRealtime()
        val devices = storage.read().getJSONArray("devices")
        val device = (0 until devices.length()).map {devices.getJSONObject(it)}.find {it.getString("deviceId") == deviceId}
            ?: throw IllegalArgumentException("请先配对电脑")
        val group = JSONObject(payload); val images = group.getJSONArray("images"); val id = group.getString("requestId")
        require(images.length() in 1..10 && Regex("[a-f0-9-]{36}").matches(id)) {"图集编号或数量无效"}
        val files = (0 until images.length()).map {index ->
            val image = images.getJSONObject(index); val file = File(image.getString("path")); val type = image.getString("mime")
            require(file.canonicalFile.parentFile == File(context.cacheDir, "outbox").canonicalFile && file.length() in 1..33554432L) {"图片已过期或超过大小限制"}
            require(type in listOf("image/png", "image/jpeg")) {"图集暂只支持静态图片"}
            Pair(file, type)
        }
        require(files.sumOf {it.first.length()} <= 100000000L) {"整组超过 100 MB，请拆分发送"}
        val client = PinnedClient(discovery.refresh(device))
        val result = try {client.request("/v1/batches", requestId = id, batch = files)}
            catch (exception: IllegalStateException) {try {client.request("/v1/transfers/$id")} catch (_: Exception) {throw exception}}
        if (result.optString("status") == "copied") files.forEach {Outbox.discard(context.cacheDir, it.first)}
        result.put("phoneTemporaryFiles", File(context.cacheDir, "outbox").listFiles()?.count {it.isFile} ?: 0)
        result.put("clientElapsedMs", android.os.SystemClock.elapsedRealtime() - started).toString()
    }
    @ReactMethod fun discard(path: String) {executor.execute {Outbox.discard(context.cacheDir, File(path))}}
    @ReactMethod fun send(deviceId: String, imageJson: String, promise: Promise) = work(promise) {
        val started = android.os.SystemClock.elapsedRealtime()
        val data = storage.read(); val devices = data.getJSONArray("devices")
        val device = (0 until devices.length()).map { devices.getJSONObject(it) }.find { it.getString("deviceId") == deviceId }
            ?: throw IllegalArgumentException("请先配对电脑")
        val image = JSONObject(imageJson); val file = File(image.getString("path"))
        require(file.canonicalPath.startsWith(context.cacheDir.canonicalPath + File.separator) && file.exists()) { "图片已过期，请重新分享或拍照" }
        val isVideo = image.getString("mime") == "video/mp4"
        require(file.length() in 1..(if (isVideo) 100000000L else 32L * 1024 * 1024)) { "文件超过大小限制" }
        val id = image.getString("requestId")
        require(Regex("[a-f0-9-]{36}").matches(id)) { "请求编号无效" }
        val client = PinnedClient(discovery.refresh(device))
        val result = try {client.request(if (isVideo) "/v1/videos" else "/v1/images", image = file, mime = image.getString("mime"), requestId = id)}
        catch (exception: IllegalStateException) {
            try {client.request("/v1/transfers/$id")}
            catch (_: Exception) {throw exception}
        }
        if (result.optString("status") == "copied") Outbox.discard(context.cacheDir, file)
        result.put("phoneTemporaryFiles", File(context.cacheDir, "outbox").listFiles()?.count {it.isFile} ?: 0)
        result.put("clientElapsedMs", android.os.SystemClock.elapsedRealtime() - started).toString()
    }
    override fun invalidate() {discovery.stop(); executor.shutdown(); super.invalidate()}
}
