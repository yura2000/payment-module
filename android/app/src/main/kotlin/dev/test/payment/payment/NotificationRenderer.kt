package dev.test.payment.payment

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import dev.test.payment.R

/** Turns a [NotificationSpec] into a real notification. Android-only; not unit-tested. */
internal class NotificationRenderer(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    /** `IMPORTANCE_LOW`: silent, no heads-up, still in the status bar. minSdk 26 — no version gate. */
    fun ensureChannel() {
        manager.createNotificationChannel(
            NotificationChannel(
                PaymentJobNotifications.CHANNEL_ID,
                "Payment processing",
                NotificationManager.IMPORTANCE_LOW,
            ),
        )
    }

    fun render(spec: NotificationSpec): Notification =
        NotificationCompat.Builder(context, PaymentJobNotifications.CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_payment)
            .setContentTitle(spec.title)
            .setContentText(spec.text)
            .setOngoing(spec.ongoing)
            .setAutoCancel(!spec.ongoing)
            .setOnlyAlertOnce(true)
            .setContentIntent(launchIntent())
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .apply { spec.progressPercent?.let { setProgress(100, it, false) } }
            .build()

    /** Silently dropped by the system when POST_NOTIFICATIONS is denied — the job is unaffected. */
    fun show(spec: NotificationSpec) {
        manager.notify(PaymentJobNotifications.NOTIFICATION_ID, render(spec))
    }

    /** Tapping opens the app; the root route re-attaches through `current` (§10). */
    private fun launchIntent(): PendingIntent? =
        context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
            PendingIntent.getActivity(
                context,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
}
