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
    fun hardwareStepDetectorCountsEachCallback() {
        val window = StepWindow()
        assertEquals(1, window.detectedStep())
        assertEquals(2, window.detectedStep())
    }
}
