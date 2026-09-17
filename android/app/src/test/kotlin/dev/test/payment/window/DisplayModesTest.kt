package dev.test.payment.window

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DisplayModesTest {
    private val current60 = DisplayModeOption(modeId = 1, width = 1080, height = 2400, refreshRate = 60f)
    private val native120 = DisplayModeOption(modeId = 2, width = 1080, height = 2400, refreshRate = 120f)
    private val native90 = DisplayModeOption(modeId = 3, width = 1080, height = 2400, refreshRate = 90f)
    private val highRes144 = DisplayModeOption(modeId = 4, width = 1440, height = 3200, refreshRate = 144f)

    @Test
    fun `picks the highest rate at the current resolution, never switching resolution`() {
        val choice = DisplayModes.highestRefreshRate(listOf(current60, native120, native90, highRes144), current60)
        assertEquals(native120, choice)
    }

    @Test
    fun `no mode at the current resolution means no preference`() {
        assertNull(DisplayModes.highestRefreshRate(listOf(highRes144), current60))
    }

    @Test
    fun `the reply matches preferHighRefreshRate_result fixture`() {
        assertEquals(ContractFixtures.load("preferHighRefreshRate.result"), ContractFixtures.normalized(native120.toWire()))
    }
}
