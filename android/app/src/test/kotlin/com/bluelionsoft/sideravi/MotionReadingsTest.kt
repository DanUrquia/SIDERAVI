package com.bluelionsoft.sideravi

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MotionReadingsTest {
    @Test
    fun screenTopTurnsClockwiseWithinTheReferencePlane() {
        assertEquals(0.0, screenTopAzimuth(0.0, 1.0)!!, 0.0001)
        assertEquals(90.0, screenTopAzimuth(1.0, 0.0)!!, 0.0001)
        assertEquals(-90.0, screenTopAzimuth(-1.0, 0.0)!!, 0.0001)
        assertNull(screenTopAzimuth(0.1, 0.1))
    }

    @Test
    fun counterCountsOnlyIncreasesInsideTheActiveWindow() {
        val window = StepWindow()
        assertEquals(0, window.counter(12_050))
        assertEquals(3, window.counter(12_053))
        assertEquals(3, window.counter(12_053))
        assertEquals(3, window.counter(10))
        assertEquals(5, window.counter(12))
        assertEquals(0, StepWindow().counter(12))
    }

    @Test
    fun counterAndDetectorDoNotCountOverlappingStepsTwice() {
        val feed = StepFeed(true)
        fun counter(time: Long, count: Int) = feed.counter(time * 1_000_000_000, count)
        fun detector(time: Long) = feed.detector(time * 1_000_000_000)
        assertEquals(emptyList<StepFeed.Reading>(), counter(1, 75))
        assertEquals(emptyList<StepFeed.Reading>(), detector(2))
        assertEquals(emptyList<StepFeed.Reading>(), detector(3))
        assertEquals(2, counter(3, 77).single().total)
        assertEquals(emptyList<StepFeed.Reading>(), detector(3))
        assertEquals(emptyList<StepFeed.Reading>(), counter(3, 78))
        assertEquals(emptyList<StepFeed.Reading>(), counter(4, 2))
        assertEquals(3, counter(5, 3).single().total)
        detector(6)
        assertEquals(emptyList<StepFeed.Reading>(), feed.flush(8_000_000_000))
        val fallback = feed.flush(9_000_000_000)
        assertEquals(4, fallback.single().total)
        assertEquals("androidStepDetector", fallback.single().source)
        assertEquals(emptyList<StepFeed.Reading>(), counter(10, 4))
        assertEquals(5, detector(10).single().total)
    }

    @Test
    fun lateInitialBaselineCannotEraseDetectorSteps() {
        val feed = StepFeed(true)
        feed.detector(1)
        feed.detector(2)
        assertEquals(emptyList<StepFeed.Reading>(), feed.counter(2, 200))
        feed.detector(3)
        assertEquals(listOf(1, 2, 3), feed.counter(3, 201).map { it.total })
        assertEquals(emptyList<StepFeed.Reading>(), feed.counter(4, 202))
    }

    @Test
    fun counterCanUseAnOlderHardwareSnapshotAsTheBaseline() {
        val feed = StepFeed(true, startedAt = 100)
        assertEquals(emptyList<StepFeed.Reading>(), feed.counter(90, 420))
        assertEquals(emptyList<StepFeed.Reading>(), feed.counter(98, 422))
        assertEquals(emptyList<StepFeed.Reading>(), feed.detector(99))
        assertEquals(3, feed.counter(105, 425).single().total)
        assertEquals(emptyList<StepFeed.Reading>(), feed.counter(104, 426))
    }

    @Test
    fun detectorOnlyCountsUniqueCallbacksAndRestartsCleanly() {
        val feed = StepFeed(false)
        assertEquals(1, feed.detector(10).single().total)
        assertEquals(emptyList<StepFeed.Reading>(), feed.detector(10))
        assertEquals(emptyList<StepFeed.Reading>(), feed.detector(9))
        assertEquals(2, feed.detector(11).single().total)
        assertEquals(1, StepFeed(false).detector(12).single().total)
    }
}
