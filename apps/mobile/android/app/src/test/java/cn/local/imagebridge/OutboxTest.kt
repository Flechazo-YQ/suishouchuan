package cn.local.imagebridge

import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.nio.file.Files

class OutboxTest {
    @Test fun discardRemovesOnlyTheCurrentPrivateMedia() {
        val cache = Files.createTempDirectory("imagebridge-outbox-").toFile()
        try {
            val photo = Outbox.create(cache, "jpg").apply {writeText("photo")}
            val retry = Outbox.create(cache, "mp4").apply {writeText("pending retry")}
            Outbox.discard(cache, photo)
            assertFalse(photo.exists()); assertTrue(retry.exists())
            Outbox.discard(cache, photo)
            assertTrue(retry.exists())
        } finally {cache.deleteRecursively()}
    }
    @Test fun restartClearsAbandonedPrivateFilesButDoesNotTouchTheSource() {
        val cache = Files.createTempDirectory("imagebridge-outbox-").toFile()
        try {
            Outbox.create(cache, "jpg").writeText("abandoned preview")
            Outbox.create(cache, "mp4").writeText("abandoned recording")
            val source = File(cache, "original-gallery.jpg").apply {writeText("keep original")}
            Outbox.clear(cache)
            assertEquals(0, File(cache, "outbox").listFiles()!!.size)
            assertTrue(source.exists())
            try {Outbox.discard(cache, source); fail("Must reject files outside the outbox")}
            catch (_: IllegalArgumentException) {assertTrue(source.exists())}
        } finally {cache.deleteRecursively()}
    }
}
