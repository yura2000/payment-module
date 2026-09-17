package dev.test.payment.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RootChecksTest {
    private fun fires(name: String) = RootSignal(name) { true }

    private fun quiet(name: String) = RootSignal(name) { false }

    private fun throws(name: String) = RootSignal(name) { throw SecurityException("denied") }

    @Test
    fun `no signal fired is clear`() {
        val outcome = RootChecks(listOf(quiet("a"), quiet("b"))).run()
        assertEquals(AssessmentResult.Clear, outcome.result)
    }

    @Test
    fun `one signal alone is below the threshold and stays clear`() {
        val outcome = RootChecks(listOf(fires("a"), quiet("b"), quiet("c"))).run()
        assertEquals(AssessmentResult.Clear, outcome.result)
        assertEquals(listOf("a"), outcome.fired)
    }

    @Test
    fun `two signals reach the threshold and are detected`() {
        val outcome = RootChecks(listOf(fires("a"), quiet("b"), fires("c"))).run()
        assertEquals(AssessmentResult.Detected, outcome.result)
        assertEquals(listOf("a", "c"), outcome.fired)
    }

    @Test
    fun `a signal that throws below the threshold is unavailable(error), never clear`() {
        val outcome = RootChecks(listOf(fires("a"), throws("b"), quiet("c"))).run()
        assertEquals(AssessmentResult.Unavailable(UnavailableReason.ERROR), outcome.result)
        assertEquals(listOf("b"), outcome.failed)
    }

    @Test
    fun `a signal that throws does not mask a detection`() {
        val outcome = RootChecks(listOf(fires("a"), throws("b"), fires("c"))).run()
        assertEquals(AssessmentResult.Detected, outcome.result)
    }

    @Test
    fun `read-write system and vendor mounts are writable`() {
        assertTrue(RootChecks.isWritableSystemMount("/dev/block/dm-0 /system ext4 rw,seclabel,relatime 0 0"))
        assertTrue(RootChecks.isWritableSystemMount("/dev/block/dm-2 /vendor ext4 rw 0 0"))
    }

    @Test
    fun `read-only, nested and malformed mounts are not`() {
        assertFalse(RootChecks.isWritableSystemMount("/dev/block/dm-0 /system ext4 ro,seclabel,relatime 0 0"))
        assertFalse(RootChecks.isWritableSystemMount("tmpfs /system/etc tmpfs rw 0 0"))
        assertFalse(RootChecks.isWritableSystemMount("/dev/root /system"))
    }
}
