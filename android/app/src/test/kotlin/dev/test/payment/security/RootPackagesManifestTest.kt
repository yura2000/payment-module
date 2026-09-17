package dev.test.payment.security

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

class RootPackagesManifestTest {
    @Test
    fun `every root package has a manifest queries entry and vice versa`() {
        val manifest = File(System.getProperty("main.manifest") ?: error("Run through Gradle: main.manifest is unset")).readText()
        val queried = Regex("""<package\s+android:name="([^"]+)"""").findAll(manifest).map { it.groupValues[1] }.toSet()
        assertEquals(RootChecks.ROOT_PACKAGES.toSet(), queried)
    }
}
