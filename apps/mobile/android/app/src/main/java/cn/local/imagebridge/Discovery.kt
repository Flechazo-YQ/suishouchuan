package cn.local.imagebridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

class Discovery(context: Context) {
    private val manager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private val found = ConcurrentHashMap<String, JSONObject>()
    private var listener: NsdManager.DiscoveryListener? = null
    fun start() {
        if (listener != null) return
        val callback = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) {listener = null}
            override fun onStopDiscoveryFailed(type: String, error: Int) {listener = null}
            override fun onServiceLost(service: NsdServiceInfo) {found.remove(service.serviceName)}
            override fun onServiceFound(service: NsdServiceInfo) {resolve(service)}
        }
        listener = callback
        try {manager.discoverServices("_imagebridge._tcp.", NsdManager.PROTOCOL_DNS_SD, callback)}
        catch (_: SecurityException) {listener = null}
    }
    @Suppress("DEPRECATION") private fun resolve(service: NsdServiceInfo) {
        manager.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, error: Int) {}
            override fun onServiceResolved(info: NsdServiceInfo) {
                val id = info.attributes["id"]?.toString(Charsets.UTF_8) ?: return
                val address = info.host?.hostAddress ?: return
                if (!PinnedClient.privateAddress(address)) return
                found[info.serviceName] = JSONObject().put("deviceId", id).put("name", info.attributes["name"]?.toString(Charsets.UTF_8) ?: info.serviceName)
                    .put("addresses", JSONArray().put(address)).put("port", info.port)
            }
        })
    }
    fun list(): JSONArray = JSONArray(found.values.toList())
    fun refresh(device: JSONObject): JSONObject {
        val match = found.values.find { it.optString("deviceId") == device.optString("deviceId") }
        if (match != null) {device.put("addresses", match.getJSONArray("addresses")); device.put("port", match.getInt("port"))}
        return device
    }
    fun stop() {listener?.let {callback -> try {manager.stopServiceDiscovery(callback)} catch (_: IllegalArgumentException) { } }; listener = null; found.clear()}
}
