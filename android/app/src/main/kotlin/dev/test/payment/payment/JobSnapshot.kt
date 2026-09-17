package dev.test.payment.payment

enum class PaymentFailure(val wire: String) {
    DECLINED("declined"),
    TIMED_OUT("timedOut"),
    SERVICE_UNAVAILABLE("serviceUnavailable"),
}

/** One `payment.job/events` payload, and the value `current` returns (docs/architecture.md §9). */
sealed interface JobSnapshot {
    val jobId: String
    val isTerminal: Boolean get() = this !is Running

    data class Running(override val jobId: String, val percent: Int) : JobSnapshot

    data class Succeeded(override val jobId: String, val reference: String, val completedAt: Long) : JobSnapshot

    data class Failed(override val jobId: String, val failure: PaymentFailure) : JobSnapshot

    fun toWire(): Map<String, Any?> =
        when (this) {
            is Running -> mapOf("jobId" to jobId, "state" to "running", "percent" to percent)
            is Succeeded ->
                mapOf("jobId" to jobId, "state" to "succeeded", "reference" to reference, "completedAt" to completedAt)
            is Failed -> mapOf("jobId" to jobId, "state" to "failed", "failure" to failure.wire)
        }
}
