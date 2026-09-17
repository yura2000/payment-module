package dev.test.payment.payment

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentJobStateHolderTest {
    private val holder = PaymentJobStateHolder()

    @Test
    fun `tryStart claims an idle holder as running(0)`() {
        assertTrue(holder.tryStart("j-1"))
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)
    }

    @Test
    fun `tryStart is refused while a job is running`() {
        holder.tryStart("j-1")
        assertFalse(holder.tryStart("j-2"))
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)
    }

    @Test
    fun `tryStart replaces an undelivered terminal snapshot`() {
        holder.tryStart("j-1")
        holder.advance(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED))
        assertTrue(holder.tryStart("j-2"))
        assertEquals(JobSnapshot.Running("j-2", 0), holder.state.value)
    }

    @Test
    fun `advance moves the running job forward`() {
        holder.tryStart("j-1")
        assertTrue(holder.advance(JobSnapshot.Running("j-1", 40)))
        assertEquals(JobSnapshot.Running("j-1", 40), holder.state.value)
    }

    @Test
    fun `advance never overwrites a terminal snapshot`() {
        holder.tryStart("j-1")
        holder.advance(JobSnapshot.Succeeded("j-1", "PAY-1", 1L))
        assertFalse(holder.advance(JobSnapshot.Failed("j-1", PaymentFailure.SERVICE_UNAVAILABLE)))
        assertEquals(JobSnapshot.Succeeded("j-1", "PAY-1", 1L), holder.state.value)
    }

    @Test
    fun `advance ignores another job's snapshot`() {
        holder.tryStart("j-1")
        assertFalse(holder.advance(JobSnapshot.Running("j-other", 50)))
    }

    @Test
    fun `abandon undoes tryStart`() {
        holder.tryStart("j-1")
        holder.abandon("j-1")
        assertNull(holder.state.value)
    }

    @Test
    fun `current returns a running job and keeps it`() {
        holder.tryStart("j-1")
        assertEquals(JobSnapshot.Running("j-1", 0), holder.current())
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)
    }

    @Test
    fun `current delivers a terminal snapshot once, then the holder is clear`() {
        holder.tryStart("j-1")
        holder.advance(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED))
        assertEquals(JobSnapshot.Failed("j-1", PaymentFailure.DECLINED), holder.current())
        assertNull(holder.current())
    }

    @Test
    fun `markDelivered clears only the terminal snapshot it was given`() {
        holder.tryStart("j-1")
        holder.markDelivered(JobSnapshot.Running("j-1", 0))
        assertEquals(JobSnapshot.Running("j-1", 0), holder.state.value)

        val done = JobSnapshot.Succeeded("j-1", "PAY-1", 1L)
        holder.advance(done)
        holder.markDelivered(done)
        assertNull(holder.state.value)
    }
}
