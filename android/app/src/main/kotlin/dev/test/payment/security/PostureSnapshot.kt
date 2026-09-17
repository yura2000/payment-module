package dev.test.payment.security

/** The `result` of one Threat Assessment on the wire (docs/architecture.md §9). */
sealed interface AssessmentResult {
    data object Detected : AssessmentResult

    data object Clear : AssessmentResult

    data class Unavailable(val reason: UnavailableReason) : AssessmentResult
}

enum class UnavailableReason(val wire: String) {
    API_LEVEL("apiLevel"),
    ERROR("error"),
}

/** One `security.environment/events` payload: an assessment per Threat kind, and when it was taken. */
data class PostureSnapshot(
    val rooted: AssessmentResult,
    val screenRecording: AssessmentResult,
    val assessedAt: Long,
) {
    fun toWire(): Map<String, Any?> =
        mapOf(
            "assessments" to listOf(assessment("rooted", rooted), assessment("screenRecording", screenRecording)),
            "assessedAt" to assessedAt,
        )

    private fun assessment(kind: String, result: AssessmentResult): Map<String, Any?> =
        when (result) {
            AssessmentResult.Detected -> mapOf("kind" to kind, "result" to "detected")
            AssessmentResult.Clear -> mapOf("kind" to kind, "result" to "clear")
            is AssessmentResult.Unavailable ->
                mapOf("kind" to kind, "result" to "unavailable", "reason" to result.reason.wire)
        }
}
