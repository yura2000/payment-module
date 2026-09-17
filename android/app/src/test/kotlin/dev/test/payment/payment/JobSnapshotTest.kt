package dev.test.payment.payment

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JobSnapshotTest {
    private fun assertMatches(fixture: String, snapshot: JobSnapshot) =
        assertEquals(ContractFixtures.load(fixture), ContractFixtures.normalized(snapshot.toWire()))

    @Test
    fun `running matches job_running fixture`() = assertMatches("job.running", JobSnapshot.Running("j-1", 40))

    @Test
    fun `succeeded matches job_succeeded fixture`() =
        assertMatches("job.succeeded", JobSnapshot.Succeeded("j-1", "PAY-DEMO-0001", 1758000000000L))

    @Test
    fun `declined matches job_failed-declined fixture`() =
        assertMatches("job.failed-declined", JobSnapshot.Failed("j-1", PaymentFailure.DECLINED))

    @Test
    fun `timed out matches job_failed-timedOut fixture`() =
        assertMatches("job.failed-timedOut", JobSnapshot.Failed("j-1", PaymentFailure.TIMED_OUT))

    @Test
    fun `only running is non-terminal`() {
        assertFalse(JobSnapshot.Running("j-1", 100).isTerminal)
        assertTrue(JobSnapshot.Succeeded("j-1", "r", 0).isTerminal)
        assertTrue(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED).isTerminal)
    }
}
