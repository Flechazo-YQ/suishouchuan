package cn.local.imagebridge

// A static screen may produce only one frame after the overlay disappears.
internal class CaptureFrames<T : AutoCloseable> {
    private var pending = false
    private var latest: T? = null

    fun begin() {cancel(); pending = true}
    fun offer(frame: T) {
        if (!pending) {frame.close(); return}
        latest?.close()
        latest = frame
    }
    fun take(): T? {
        val frame = latest ?: return null
        latest = null; pending = false
        return frame
    }
    fun cancel() {pending = false; latest?.close(); latest = null}
}
