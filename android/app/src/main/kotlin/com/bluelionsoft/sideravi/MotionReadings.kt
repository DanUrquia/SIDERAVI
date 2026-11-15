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
}

/** Reconciles the cumulative counter and timestamped detector in one foreground window. */
internal class StepFeed(counterAvailable: Boolean, private val startedAt: Long = Long.MIN_VALUE) {
    data class Reading(val time: Long, val total: Int, val source: String)

    private val counter = StepWindow()
    private val pendingDetector = ArrayDeque<Long>()
    private var counterTime: Long? = null
    private var counterTotal = 0
    private var coveredThrough = Long.MIN_VALUE
    private var lastDetector = Long.MIN_VALUE
    private var detectorSelected = !counterAvailable
    private var total = 0

    fun counter(time: Long, value: Int): List<Reading> {
        val previousTime = counterTime
        if (detectorSelected || value < 0 || (previousTime != null && time <= previousTime)) {
            return emptyList()
        }
        counterTime = time
        val updated = counter.counter(value)
        val increment = updated - counterTotal
        counterTotal = updated
        // The initial snapshot can carry the time of a step taken before registration.
        // Keep its total as the baseline without moving for anything in that window.
        if (increment == 0 || time < startedAt) return emptyList()

        // The first counter snapshot can already contain steps taken since registration.
        // When the detector saw those steps, use its window rather than dropping them.
        if (total == 0 && previousTime != null &&
            pendingDetector.firstOrNull()?.let { it <= previousTime } == true) {
            return switchToDetector()
        }
        coveredThrough = time
        while (pendingDetector.firstOrNull()?.let { it <= time } == true) {
            pendingDetector.removeFirst()
        }
        total += increment
        return listOf(Reading(time, total, "androidStepCounter"))
    }

    fun detector(time: Long): List<Reading> {
        if (time < startedAt || time <= lastDetector || time <= coveredThrough) return emptyList()
        lastDetector = time
        if (detectorSelected) return listOf(detectorReading(time))
        pendingDetector.addLast(time)
        return emptyList()
    }

    // The counter can be delayed. Wait briefly for an overlapping counter update,
    // then take the live detector as the sole source for the rest of this window.
    fun flush(now: Long): List<Reading> =
        if (pendingDetector.firstOrNull()?.let { now - it >= 3_000_000_000L } == true) {
            switchToDetector()
        } else {
            emptyList()
        }

    private fun switchToDetector(): List<Reading> {
        detectorSelected = true
        val readings = pendingDetector.map(::detectorReading)
        pendingDetector.clear()
        return readings
    }

    private fun detectorReading(time: Long) = Reading(time, ++total, "androidStepDetector")
}
