package dev.test.payment.payment

import org.junit.Assert.assertEquals
import org.junit.Test

class PaymentJobNotificationsTest {
    @Test
    fun `a running job is an ongoing progress notification`() {
        assertEquals(
            NotificationSpec("Processing payment", "40%", progressPercent = 40, ongoing = true),
            PaymentJobNotifications.specFor(JobSnapshot.Running("j", 40)),
        )
    }

    @Test
    fun `success is a dismissible notification with the reference and no progress bar`() {
        assertEquals(
            NotificationSpec("Payment complete", "Reference PAY-1", progressPercent = null, ongoing = false),
            PaymentJobNotifications.specFor(JobSnapshot.Succeeded("j", "PAY-1", 0)),
        )
    }

    @Test
    fun `each failure has its own dismissible title`() {
        val titles =
            PaymentFailure.entries.map { PaymentJobNotifications.specFor(JobSnapshot.Failed("j", it)) }
        assertEquals(
            listOf("Payment declined", "Payment timed out", "Payment could not be processed"),
            titles.map { it.title },
        )
        titles.forEach {
            assertEquals(null, it.progressPercent)
            assertEquals(false, it.ongoing)
        }
    }
}
