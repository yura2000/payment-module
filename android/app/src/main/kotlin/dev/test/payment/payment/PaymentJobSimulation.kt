package dev.test.payment.payment

/**
 * The simulated processor (docs/architecture.md §5, §10): +5 % every 250 ms; an amount whose minor
 * units end in 99 is declined at 60 %; anything else succeeds at 100 %.
 */
object PaymentJobSimulation {
    const val TICK_MS = 250L
    const val STEP_PERCENT = 5
    const val DECLINE_AT_PERCENT = 60

    fun declines(amountMinor: Long): Boolean = amountMinor % 100 == 99L

    /** The snapshot once the job has reached [percent]. */
    fun snapshotAt(
        jobId: String,
        args: StartArgs,
        percent: Int,
        now: () -> Long,
    ): JobSnapshot =
        when {
            declines(args.amountMinor) && percent >= DECLINE_AT_PERCENT ->
                JobSnapshot.Failed(jobId, PaymentFailure.DECLINED)
            percent >= 100 -> JobSnapshot.Succeeded(jobId, args.reference, now())
            else -> JobSnapshot.Running(jobId, percent)
        }
}
