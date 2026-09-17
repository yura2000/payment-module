package dev.test.payment.payment

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The Payment Job's state, for the whole process (docs/architecture.md §10). The service is its
 * only writer after [tryStart]; the channel handler only reads, and clears a terminal snapshot
 * once it has been delivered. [shared] is the process-wide instance; the class is instantiable so
 * JVM tests get a fresh one each.
 */
class PaymentJobStateHolder {
    private val mutableState = MutableStateFlow<JobSnapshot?>(null)
    val state: StateFlow<JobSnapshot?> = mutableState.asStateFlow()

    /** Claims the holder for [jobId] as `running(0)` unless a job is already running. */
    fun tryStart(jobId: String): Boolean {
        while (true) {
            val current = mutableState.value
            if (current is JobSnapshot.Running) return false
            if (mutableState.compareAndSet(current, JobSnapshot.Running(jobId, 0))) return true
        }
    }

    /**
     * Moves the running job [JobSnapshot.jobId] forward to [snapshot]. Refused — returns false —
     * once that job has left `running`, so a terminal snapshot is never overwritten.
     */
    fun advance(snapshot: JobSnapshot): Boolean {
        while (true) {
            val current = mutableState.value
            if (current !is JobSnapshot.Running || current.jobId != snapshot.jobId) return false
            if (mutableState.compareAndSet(current, snapshot)) return true
        }
    }

    /** Undoes [tryStart] when the service could not be started. */
    fun abandon(jobId: String) {
        mutableState.compareAndSet(JobSnapshot.Running(jobId, 0), null)
    }

    /** The `current` reply. Reading a terminal snapshot delivers it, which clears it. */
    fun current(): JobSnapshot? = mutableState.value?.also { if (it.isTerminal) markDelivered(it) }

    /** Clears [snapshot] if it is still the current, terminal state — replay-until-delivered. */
    fun markDelivered(snapshot: JobSnapshot) {
        if (snapshot.isTerminal) mutableState.compareAndSet(snapshot, null)
    }

    companion object {
        val shared = PaymentJobStateHolder()
    }
}
