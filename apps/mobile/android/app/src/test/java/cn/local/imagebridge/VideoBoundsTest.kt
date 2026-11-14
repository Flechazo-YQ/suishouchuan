package cn.local.imagebridge

import org.junit.Assert.assertEquals
import org.junit.Test

class VideoBoundsTest {
    @Test fun tallScreenRecordingKeepsItsRatioInShorterPreview() {
        assertEquals(VideoBounds(729, 1620), fitVideoBounds(1080, 1620, 1080, 2400))
    }

    @Test fun landscapeVideoFitsWithoutCropping() {
        assertEquals(VideoBounds(1080, 608), fitVideoBounds(1080, 1620, 1920, 1080))
    }

    @Test fun layoutChangeRecomputesPortraitFit() {
        assertEquals(VideoBounds(486, 1080), fitVideoBounds(2400, 1080, 1080, 2400))
    }

    @Test fun unknownDimensionsDoNotDivideByZeroOrStretch() {
        assertEquals(VideoBounds(0, 0), fitVideoBounds(1080, 1620, 0, 0))
        assertEquals(VideoBounds(0, 0), fitVideoBounds(0, 0, 1080, 2400))
    }
}
