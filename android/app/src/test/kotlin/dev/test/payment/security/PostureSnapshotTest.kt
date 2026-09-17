package dev.test.payment.security

import dev.test.payment.ContractFixtures
import org.junit.Assert.assertEquals
import org.junit.Test

class PostureSnapshotTest {
    private val assessedAt = 1758000000000L

    @Test
    fun `secure snapshot matches posture_secure fixture`() {
        val snapshot = PostureSnapshot(AssessmentResult.Clear, AssessmentResult.Clear, assessedAt)
        assertEquals(ContractFixtures.load("posture.secure"), ContractFixtures.normalized(snapshot.toWire()))
    }

    @Test
    fun `rooted snapshot matches posture_compromised-rooted fixture`() {
        val snapshot = PostureSnapshot(AssessmentResult.Detected, AssessmentResult.Clear, assessedAt)
        assertEquals(ContractFixtures.load("posture.compromised-rooted"), ContractFixtures.normalized(snapshot.toWire()))
    }

    @Test
    fun `below API 35 snapshot matches posture_unverified-api34 fixture`() {
        val snapshot =
            PostureSnapshot(
                rooted = AssessmentResult.Clear,
                screenRecording = AssessmentResult.Unavailable(UnavailableReason.API_LEVEL),
                assessedAt = assessedAt,
            )
        assertEquals(ContractFixtures.load("posture.unverified-api34"), ContractFixtures.normalized(snapshot.toWire()))
    }
}
