package cn.local.imagebridge

import kotlin.math.min
import kotlin.math.roundToInt

data class VideoBounds(val width: Int, val height: Int)

fun fitVideoBounds(containerWidth: Int, containerHeight: Int, videoWidth: Int, videoHeight: Int): VideoBounds {
    if (containerWidth <= 0 || containerHeight <= 0 || videoWidth <= 0 || videoHeight <= 0) return VideoBounds(0, 0)
    val scale = min(containerWidth.toDouble() / videoWidth, containerHeight.toDouble() / videoHeight)
    return VideoBounds((videoWidth * scale).roundToInt().coerceAtMost(containerWidth),
        (videoHeight * scale).roundToInt().coerceAtMost(containerHeight))
}
