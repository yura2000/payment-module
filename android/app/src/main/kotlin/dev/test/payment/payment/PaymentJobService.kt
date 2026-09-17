package dev.test.payment.payment

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The simulated Payment Job, as a `shortService` foreground service (docs/architecture.md §10).
 * Started, never bound. Writes every snapshot to [PaymentJobStateHolder]; the three teardown
 * writers — the ticker's terminal tick, [onTimeout], [onDestroy] — all go through
 * [PaymentJobStateHolder.advance], so whichever lands first wins and the others are no-ops.
 * Stops with the latest start id, so a retry that starts a new job while this instance is still
 * winding down is not dropped.
 */
class PaymentJobService : Service() {
    private val holder = PaymentJobStateHolder.shared
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var notifications: NotificationRenderer
    /** The job this instance is ticking; `null` once it has finished. Main thread only. */
    private var jobId: String? = null

    /**
     * The newest start id. [finish] stops with it, so a start that arrived after the finishing job's
     * own keeps the service alive. [finish] always runs before the next job's [onStartCommand]: its
     * main-thread continuation is queued before the terminal snapshot even reaches Dart, and a new
     * `start` needs further main-thread round trips after that.
     */
    private var lastStartId = 0

    override fun onCreate() {
        super.onCreate()
        notifications = NotificationRenderer(this)
        notifications.ensureChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStartId = startId
        // startForeground must run within 5 s of startForegroundService, whatever happens next.
        ServiceCompat.startForeground(
            this,
            PaymentJobNotifications.NOTIFICATION_ID,
            notifications.render(PaymentJobNotifications.progress(0)),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            } else {
                0
            },
        )
        val newJobId = intent?.getStringExtra(EXTRA_JOB_ID)
        val args = intent?.let(StartArgs::readFrom)
        when {
            // The holder admits one running job at a time, so a ticking instance never gets a second.
            jobId != null -> Unit
            newJobId != null && args != null -> {
                jobId = newJobId
                scope.launch { tick(newJobId, args) }
            }
            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    /** API 34's `shortService` timeout. */
    override fun onTimeout(startId: Int) = timedOut()

    /** API 35+'s typed timeout; overridden too so the outcome doesn't depend on which one the OS calls. */
    override fun onTimeout(startId: Int, fgsType: Int) = timedOut()

    override fun onDestroy() {
        jobId?.let { holder.advance(JobSnapshot.Failed(it, PaymentFailure.SERVICE_UNAVAILABLE)) }
        scope.cancel()
        super.onDestroy()
    }

    private suspend fun tick(jobId: String, args: StartArgs) {
        var percent = 0
        while (true) {
            delay(PaymentJobSimulation.TICK_MS)
            percent += PaymentJobSimulation.STEP_PERCENT
            val snapshot = PaymentJobSimulation.snapshotAt(jobId, args, percent, System::currentTimeMillis)
            if (!holder.advance(snapshot)) return
            if (snapshot.isTerminal) {
                withContext(Dispatchers.Main) { finish(snapshot) }
                return
            }
            notifications.show(PaymentJobNotifications.specFor(snapshot))
        }
    }

    private fun timedOut() {
        val snapshot = jobId?.let { JobSnapshot.Failed(it, PaymentFailure.TIMED_OUT) }
        if (snapshot != null && holder.advance(snapshot)) finish(snapshot) else stopSelf(lastStartId)
    }

    /** Final notification, detached so it outlives the service, then stop. */
    private fun finish(snapshot: JobSnapshot) {
        notifications.show(PaymentJobNotifications.specFor(snapshot))
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        jobId = null
        stopSelf(lastStartId)
    }

    companion object {
        private const val EXTRA_JOB_ID = "dev.test.payment.extra.JOB_ID"

        fun intent(context: Context, jobId: String, args: StartArgs): Intent =
            args.writeTo(Intent(context, PaymentJobService::class.java).putExtra(EXTRA_JOB_ID, jobId))
    }
}
