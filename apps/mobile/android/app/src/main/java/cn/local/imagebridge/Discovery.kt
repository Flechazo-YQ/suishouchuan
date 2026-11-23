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
    @Volatile private var listener: NsdManager.DiscoveryListener? = null
    fun start() {
        if (listener != null) return
        val callback = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(type: String) {}
            override fun onDiscoveryStopped(type: String) {}
            override fun onStartDiscoveryFailed(type: String, error: Int) {if (listener === this) listener = null}
            override fun onStopDiscoveryFailed(type: String, error: Int) {if (listener === this) listener = null}
            override fun onServiceLost(service: NsdServiceInfo) {if (listener === this) found.remove(service.serviceName)}
            override fun onServiceFound(service: NsdServiceInfo) {if (listener === this) resolve(service, this)}
        }
        listener = callback
        try {manager.discoverServices("_imagebridge._tcp.", NsdManager.PROTOCOL_DNS_SD, callback)}
        catch (_: SecurityException) {listener = null}
    }
    @Suppress("DEPRECATION") private fun resolve(service: NsdServiceInfo, owner: NsdManager.DiscoveryListener) {
        manager.resolveService(service, object : NsdManager.ResolveListener {
            override fun onResolveFailed(info: NsdServiceInfo, error: Int) {}
            override fun onServiceResolved(info: NsdServiceInfo) {
                if (listener !== owner) return
                val id = info.attributes["id"]?.toString(Charsets.UTF_8) ?: return
                val address = info.host?.hostAddress ?: return
                if (!PinnedClient.privateAddress(address)) return
                found[info.serviceName] = JSONObject().put("deviceId", id).put("name", info.attributes["name"]?.toString(Charsets.UTF_8) ?: info.serviceName)
                    .put("addresses", JSONArray().put(address)).put("port", info.port)
            }
        })
    }
    fun list(): JSONArray = JSONArray(found.values.toList())
    fun endpointFor(device: JSONObject): JSONObject {
        val match = found.values.find { it.optString("deviceId").equals(device.optString("deviceId"), ignoreCase = true) } ?: return device
        return JSONObject(device.toString()).put("addresses", match.getJSONArray("addresses")).put("port", match.getInt("port"))
    }
    fun stop() {
        val previous = listener
        listener = null
        found.clear()
        if (previous != null) {
            try { manager.stopServiceDiscovery(previous) } catch (_: IllegalArgumentException) { }
        }
    }
}
