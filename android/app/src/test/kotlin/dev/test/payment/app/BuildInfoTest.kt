package dev.test.payment.app

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Test

class BuildInfoTest {
    @Test
    fun `the reply matches buildInfo_retail fixture`() {
        val info =
            BuildInfo(
                flavor = "retail",
                applicationId = "dev.test.payment.retail",
                versionName = "0.1.0",
                versionCode = 1,
                sdkInt = 36,
            )
        assertEquals(ContractFixtures.load("buildInfo.retail"), ContractFixtures.normalized(info.toWire()))
    }
}
