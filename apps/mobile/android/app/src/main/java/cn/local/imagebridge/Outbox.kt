package cn.local.imagebridge

import java.io.File
import java.util.UUID

object Outbox {
    private fun folder(cache: File) = File(cache, "outbox").apply {mkdirs()}
    fun create(cache: File, extension: String): File {
        require(extension in listOf("jpg", "png", "mp4", "source"))
        return File(folder(cache), UUID.randomUUID().toString() + "." + extension)
    }
    fun discard(cache: File, file: File) {
        require(file.canonicalFile.parentFile == folder(cache).canonicalFile) {"只能清理应用自己的临时素材"}
        if (file.isFile) file.delete()
    }
    fun clear(cache: File) {
        // Previews are not restored after process exit, so their private files are no longer needed.
        folder(cache).listFiles()?.filter {it.isFile}?.forEach {discard(cache, it)}
    }
}
