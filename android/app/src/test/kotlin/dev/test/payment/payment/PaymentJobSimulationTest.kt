package dev.test.payment.payment

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentJobSimulationTest {
    private val approved = StartArgs("PAY-1", amountMinor = 4200, currency = "USD", payee = "Acme")
    private val declined = approved.copy(amountMinor = 4299)
    private val now = { 1758000000000L }

    @Test
    fun `only amounts ending in 99 minor units are declined`() {
        assertTrue(PaymentJobSimulation.declines(99))
        assertTrue(PaymentJobSimulation.declines(4299))
        assertFalse(PaymentJobSimulation.declines(4200))
        assertFalse(PaymentJobSimulation.declines(9900))
    }

    @Test
    fun `an approved job runs until 100 then succeeds with the payment reference`() {
        assertEquals(JobSnapshot.Running("j", 95), PaymentJobSimulation.snapshotAt("j", approved, 95, now))
        assertEquals(
            JobSnapshot.Succeeded("j", "PAY-1", 1758000000000L),
            PaymentJobSimulation.snapshotAt("j", approved, 100, now),
        )
    }

    @Test
    fun `a declined job runs until 60 then fails as declined`() {
        assertEquals(JobSnapshot.Running("j", 55), PaymentJobSimulation.snapshotAt("j", declined, 55, now))
        assertEquals(
            JobSnapshot.Failed("j", PaymentFailure.DECLINED),
            PaymentJobSimulation.snapshotAt("j", declined, 60, now),
        )
    }

    @Test
    fun `the whole job takes 20 ticks of 250 ms`() {
        assertEquals(5_000L, (100 / PaymentJobSimulation.STEP_PERCENT) * PaymentJobSimulation.TICK_MS)
    }
}
