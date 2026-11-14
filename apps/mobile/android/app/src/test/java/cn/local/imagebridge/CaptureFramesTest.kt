package cn.local.imagebridge

import org.junit.Assert.*
import org.junit.Test

class CaptureFramesTest {
    private class Frame : AutoCloseable {
        var closes = 0
        override fun close() {closes++}
    }

    @Test fun staticScreenRemainsAvailableAfterOverlaySettlingDelay() {
        val frames = CaptureFrames<Frame>()
        val still = Frame()
        frames.begin()
        frames.offer(still)
        // No further callbacks occur when the compositor has no changed pixels.
        assertSame(still, frames.take())
        assertEquals(0, still.closes)
        still.close()
        assertNull(frames.take())
    }

    @Test fun movingScreenUsesNewestFrameAndReleasesOldBuffers() {
        val frames = CaptureFrames<Frame>()
        val early = Frame(); val latest = Frame()
        frames.begin(); frames.offer(early); frames.offer(latest)
        assertEquals(1, early.closes)
        assertSame(latest, frames.take())
        frames.cancel()
        assertEquals(0, latest.closes)
        latest.close()
    }

    @Test fun canceledCaptureCannotLeakAFrameIntoTheNextScreenshot() {
        val frames = CaptureFrames<Frame>()
        val canceled = Frame(); val late = Frame(); val current = Frame()
        frames.begin(); frames.offer(canceled); frames.cancel(); frames.offer(late)
        frames.begin()
        assertNull(frames.take())
        frames.offer(current)
        assertSame(current, frames.take())
        assertEquals(1, canceled.closes); assertEquals(1, late.closes)
        current.close()
    }

    @Test fun idleFramesAndInterruptedCaptureAreReleased() {
        val frames = CaptureFrames<Frame>()
        val idle = Frame(); val interrupted = Frame()
        frames.offer(idle); frames.begin(); frames.offer(interrupted); frames.begin()
        assertEquals(1, idle.closes); assertEquals(1, interrupted.closes)
        assertNull(frames.take())
        frames.cancel(); frames.cancel()
        assertEquals(1, interrupted.closes)
    }
}
