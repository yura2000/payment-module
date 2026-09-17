package dev.test.payment.payment

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class StartArgsTest {
    @Test
    fun `parses start_args fixture`() {
        assertEquals(
            StartArgs(reference = "PAY-DEMO-0001", amountMinor = 4200, currency = "USD", payee = "Acme Utilities"),
            StartArgs.fromWire(ContractFixtures.load("start.args")),
        )
    }

    @Test
    fun `accepts amountMinor as an Integer, as the codec sends small Dart ints`() {
        val args = mapOf("reference" to "r", "amountMinor" to 4299, "currency" to "USD", "payee" to "p")
        assertEquals(4299L, StartArgs.fromWire(args)?.amountMinor)
    }

    @Test
    fun `rejects a missing or mistyped field`() {
        assertNull(StartArgs.fromWire(mapOf("reference" to "r", "currency" to "USD", "payee" to "p")))
        assertNull(StartArgs.fromWire(mapOf("reference" to "r", "amountMinor" to "42", "currency" to "USD", "payee" to "p")))
        assertNull(StartArgs.fromWire(null))
    }
}
