package dev.test.payment.bridge

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Test

class ChannelNamesTest {
    @Test
    fun `channel names match contract fixtures`() {
        assertEquals(
            ContractFixtures.load("channels"),
            mapOf(
                "securityEnvironment" to ChannelNames.SECURITY_ENVIRONMENT,
                "securityEnvironmentEvents" to ChannelNames.SECURITY_ENVIRONMENT_EVENTS,
                "window" to ChannelNames.WINDOW,
                "paymentJob" to ChannelNames.PAYMENT_JOB,
                "paymentJobEvents" to ChannelNames.PAYMENT_JOB_EVENTS,
                "app" to ChannelNames.APP,
            ),
        )
    }
}
