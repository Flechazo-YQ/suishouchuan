package cn.local.imagebridge

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.os.Build
import java.io.File
import java.nio.ByteBuffer

internal object ScreenRecordingLimit {
    private const val LIMIT_US = 30_000_000L

    fun apply(cache: File, source: File): File {
        require(source.length() in 1..100000000L) {"视频上限为 100 MB"}
        val duration = durationMs(source)
        if (duration <= 30000) return source
        val output = Outbox.create(cache, "mp4")
        try {
            trim(source, output)
            val boundedDuration = durationMs(output)
            check(boundedDuration in 1..30000) {"录屏时长处理失败，请重试"}
            android.util.Log.i("ImageBridgeCapture", "Recording duration bounded: ${duration}ms -> ${boundedDuration}ms")
            Outbox.discard(cache, source)
            return output
        } catch (exception: Exception) {
            Outbox.discard(cache, output)
            throw exception
        }
    }

    private fun durationMs(file: File): Long {
        val metadata = MediaMetadataRetriever()
        try {
            metadata.setDataSource(file.path)
            return metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
        } finally {metadata.release()}
    }

    private fun trim(source: File, output: File) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(source.path)
            // ScreenRecorder creates one silent H.264 track; copying encoded samples avoids quality loss.
            check(extractor.trackCount == 1) {"录屏轨道无效"}
            val format = extractor.getTrackFormat(0)
            check(format.getString(MediaFormat.KEY_MIME)?.startsWith("video/") == true) {"录屏缺少视频轨道"}
            extractor.selectTrack(0)
            val muxer = MediaMuxer(output.path, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            try {
                val track = muxer.addTrack(format)
                muxer.start()
                copySamples(extractor, muxer, track, source.length().toInt())
                muxer.stop()
            } finally {muxer.release()}
        } finally {extractor.release()}
    }

    private fun copySamples(extractor: MediaExtractor, muxer: MediaMuxer, track: Int, fileBytes: Int) {
        // API 26/27 cannot query packet sizes; the bounded file size also bounds every packet.
        var buffer = ByteBuffer.allocateDirect(if (Build.VERSION.SDK_INT >= 28) 1024 * 1024 else fileBytes)
        val info = MediaCodec.BufferInfo()
        val firstTime = extractor.sampleTime
        check(firstTime >= 0) {"录屏没有画面"}
        while (extractor.sampleTime >= 0) {
            val time = extractor.sampleTime - firstTime
            if (time >= LIMIT_US) break
            val size = if (Build.VERSION.SDK_INT >= 28) extractor.sampleSize else buffer.capacity().toLong()
            require(size in 1..100000000L) {"录屏帧无效"}
            if (size > buffer.capacity()) buffer = ByteBuffer.allocateDirect(size.toInt())
            buffer.clear()
            val count = extractor.readSampleData(buffer, 0)
            check(count > 0) {"录屏帧读取失败"}
            val flags = if (extractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
            info.set(0, count, time, flags)
            muxer.writeSampleData(track, buffer, info)
            if (!extractor.advance()) break
        }
        // Static screens have sparse frames. Explicit EOS prevents the muxer from extending the last frame past 30s.
        info.set(0, 0, LIMIT_US, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
        muxer.writeSampleData(track, buffer, info)
    }
}
