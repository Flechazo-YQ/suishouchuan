package cn.local.imagebridge

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureStore(context: Context) {
    private val preferences = context.getSharedPreferences("imagebridge", Context.MODE_PRIVATE)
    private val alias = "imagebridge.devices"
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(alias)) {
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
                init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
                generateKey()
            }
        }
        return store.getKey(alias, null) as SecretKey
    }
    @Synchronized fun read(): JSONObject {
        val raw = preferences.getString("devices", null)
        if (raw == null) return JSONObject().put("clientId", UUID.randomUUID().toString()).put("devices", JSONArray())
        val encrypted = JSONObject(raw)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(encrypted.getString("iv"), Base64.NO_WRAP)))
        return JSONObject(String(cipher.doFinal(Base64.decode(encrypted.getString("data"), Base64.NO_WRAP)), Charsets.UTF_8))
    }
    @Synchronized fun write(data: JSONObject) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key())
        val encrypted = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("data", Base64.encodeToString(cipher.doFinal(data.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
        check(preferences.edit().putString("devices", encrypted.toString()).commit()) { "无法保存配对信息" }
    }
}
