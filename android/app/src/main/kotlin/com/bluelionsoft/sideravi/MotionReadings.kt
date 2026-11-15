package com.bluelionsoft.sideravi

import kotlin.math.atan2
import kotlin.math.hypot

/** Leaves the heading unavailable while the screen's top edge is nearly vertical. */
internal fun screenTopAzimuth(east: Double, north: Double): Double? =
    if (hypot(east, north) < .25) null else Math.toDegrees(atan2(east, north))

/** Removes the hardware's boot count from this foreground collection window. */
internal class StepWindow {
    private var previous: Int? = null
    private var total = 0

    fun counter(value: Int): Int {
        previous?.let { total += (value - it).coerceAtLeast(0) }
        previous = value
        return total
    }

    fun detectedStep(): Int = ++total
}
