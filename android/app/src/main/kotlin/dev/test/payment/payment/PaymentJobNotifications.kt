package dev.test.payment.payment

/** What the Payment Job notification shows — plain data, so it is unit-testable on the JVM. */
data class NotificationSpec(
    val title: String,
    val text: String,
    /** `null` hides the progress bar. */
    val progressPercent: Int?,
    val ongoing: Boolean,
)

/** Pure builders for the progress and final notifications (docs/architecture.md §10.2). */
object PaymentJobNotifications {
    const val CHANNEL_ID = "payment_job"
    const val NOTIFICATION_ID = 4201

    fun progress(percent: Int): NotificationSpec =
        NotificationSpec("Processing payment", "$percent%", percent, ongoing = true)

    fun specFor(snapshot: JobSnapshot): NotificationSpec =
        when (snapshot) {
            is JobSnapshot.Running -> progress(snapshot.percent)
            is JobSnapshot.Succeeded ->
                NotificationSpec("Payment complete", "Reference ${snapshot.reference}", null, ongoing = false)
            is JobSnapshot.Failed ->
                NotificationSpec(titleFor(snapshot.failure), "Open the app to try again", null, ongoing = false)
        }

    private fun titleFor(failure: PaymentFailure): String =
        when (failure) {
            PaymentFailure.DECLINED -> "Payment declined"
            PaymentFailure.TIMED_OUT -> "Payment timed out"
            PaymentFailure.SERVICE_UNAVAILABLE -> "Payment could not be processed"
        }
}
