package cn.local.imagebridge

import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.HttpsURLConnection
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManager
import javax.net.ssl.X509TrustManager

class PinnedClient(private val device: JSONObject) {
    companion object {
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        fun fileDigest(file: File): String {
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input -> val buffer = ByteArray(65536); var count = input.read(buffer)
                while (count != -1) { hash.update(buffer, 0, count); count = input.read(buffer) }
            }
            return hash.digest().joinToString("") { "%02x".format(it) }
        }
        fun privateAddress(address: String): Boolean {
            val numbers = address.split('.').map { it.toIntOrNull() ?: -1 }
            if (numbers.size != 4 || numbers.any { it !in 0..255 }) return false
            return numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168) || (numbers[0] == 172 && numbers[1] in 16..31)
        }
    }
    private fun connection(address: String, route: String): HttpsURLConnection {
        require(privateAddress(address)) { "仅支持局域网 IPv4 地址" }
        val fingerprint = device.getString("fingerprint")
        require(Regex("[a-f0-9]{64}").matches(fingerprint)) { "电脑证书指纹无效，请重新扫码" }
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<X509Certificate>, auth: String) { throw CertificateException("Unexpected client certificate") }
            override fun checkServerTrusted(chain: Array<X509Certificate>, auth: String) {
                if (chain.isEmpty() || digest(chain[0].encoded) != fingerprint) throw CertificateException("电脑证书已变化，请重新扫码配对")
                chain[0].checkValidity()
            }
        }
        val ssl = SSLContext.getInstance("TLS"); ssl.init(null, arrayOf<TrustManager>(trust), SecureRandom())
        val port = device.getInt("port"); require(port in 1..65535) { "电脑端口无效" }
        return (URL("https://$address:$port$route").openConnection() as HttpsURLConnection).apply {
            sslSocketFactory = ssl.socketFactory
            // DHCP changes the address; the paired certificate identifies the computer.
            hostnameVerifier = javax.net.ssl.HostnameVerifier { _, session -> digest(session.peerCertificates[0].encoded) == fingerprint }
            connectTimeout = 4000; readTimeout = 30000; instanceFollowRedirects = false
            setRequestProperty("Accept", "application/json")
            if (device.has("token")) setRequestProperty("Authorization", "Bearer " + device.getString("token"))
        }
    }
    fun request(route: String, json: JSONObject? = null, image: File? = null, mime: String? = null, requestId: String? = null, batch: List<Pair<File, String>>? = null): JSONObject {
        val addresses = device.getJSONArray("addresses")
        var last: Exception? = null
        for (index in 0 until addresses.length()) {
            try {return send(addresses.getString(index), route, json, image, mime, requestId, batch)}
            catch (exception: java.io.IOException) {last = exception}
        }
        throw IllegalStateException("连接电脑失败，请检查电脑是否运行、两端网络和防火墙。${last?.localizedMessage ?: "没有可用地址"}", last)
    }
    fun verifiedAddress(): String? {
        if (device.optString("token").isEmpty()) return null
        val addresses = device.getJSONArray("addresses")
        fun probe(address: String, route: String, legacy: Boolean = false): Int {
            val request = connection(address, route)
            return try {
                request.connectTimeout = 2000
                request.readTimeout = 2000
                request.useCaches = false
                val status = request.responseCode
                if (!legacy || status != 404) return status
                val error = request.errorStream?.bufferedReader()?.use { it.readText() } ?: return status
                if (JSONObject(error).optString("error") == "未找到发送记录，可以重试") 200 else status
            } finally { request.disconnect() }
        }
        for (index in 0 until addresses.length()) {
            val address = addresses.getString(index)
            if (!privateAddress(address)) continue
            try {
                val status = probe(address, "/v1/presence")
                if (status in 200..299) return address
                if (status == 404 && probe(address, "/v1/transfers/00000000-0000-0000-0000-000000000000", legacy = true) in 200..299) return address
            } catch (_: java.io.IOException) { continue }
        }
        return null
    }
    private fun send(address: String, route: String, json: JSONObject?, image: File?, mime: String?, requestId: String?, batch: List<Pair<File, String>>?): JSONObject {
        val connection = connection(address, route)
        try {
            if (batch != null) {
                val entries = JSONArray()
                batch.forEach {(file, type) -> entries.put(JSONObject().put("bytes", file.length()).put("mime", type).put("sha256", fileDigest(file)))}
                val header = JSONObject().put("images", entries).toString().toByteArray(Charsets.UTF_8)
                connection.requestMethod = "POST"; connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/x-imagebridge-batch")
                connection.setRequestProperty("X-Request-Id", requestId)
                connection.setRequestProperty("X-Content-SHA256", digest(header))
                connection.readTimeout = 120000
                connection.setFixedLengthStreamingMode(4L + header.size + batch.sumOf {it.first.length()})
                java.io.DataOutputStream(connection.outputStream).use {output ->
                    output.writeInt(header.size); output.write(header)
                    batch.forEach {(file, _) -> file.inputStream().use {it.copyTo(output, 65536)}}
                }
            } else if (image != null) {
                connection.requestMethod = "POST"; connection.doOutput = true
                connection.setRequestProperty("Content-Type", mime)
                connection.setRequestProperty("X-Request-Id", requestId)
                connection.setRequestProperty("X-Content-SHA256", fileDigest(image))
                connection.setFixedLengthStreamingMode(image.length())
                connection.outputStream.use { output -> image.inputStream().use { it.copyTo(output, 65536) } }
            } else if (json != null) {
                val data = json.toString().toByteArray(Charsets.UTF_8)
                connection.requestMethod = "POST"; connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.setFixedLengthStreamingMode(data.size)
                connection.outputStream.use { it.write(data) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: "{}"
            require(text.length <= 65536) { "电脑返回了异常数据" }
            val result = JSONObject(text)
            if (status !in 200..299) throw IllegalStateException(result.optString("error", "电脑返回错误 $status"))
            return result
        } finally { connection.disconnect() }
    }
}
