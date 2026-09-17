package dev.test.payment.payment

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.ErrorCodes
import dev.test.payment.bridge.MainThreadResult
import dev.test.payment.bridge.MainThreadSink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch
import java.util.UUID

/**
 * `payment.job` + `payment.job/events` (docs/architecture.md §9, §10). Reads
 * [PaymentJobStateHolder]; writes it only through `tryStart`/`abandon` and delivered-once
 * clearing. The event stream is replay-1: a new listener gets the current snapshot first, and a
 * terminal snapshot is cleared once it has been emitted.
 */
class PaymentJobHandler(
    private val context: Context,
    private val activity: () -> Activity?,
    private val scope: CoroutineScope,
    private val holder: PaymentJobStateHolder = PaymentJobStateHolder.shared,
) : ChannelHandler, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var collector: Job? = null
    private val pendingPermissionReplies = mutableListOf<MethodChannel.Result>()

    override fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, ChannelNames.PAYMENT_JOB).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(messenger, ChannelNames.PAYMENT_JOB_EVENTS).also { it.setStreamHandler(this) }
    }

    override fun detach() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        collector?.cancel()
        collector = null
        pendingPermissionReplies.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "ensureNotificationPermission" -> ensureNotificationPermission(reply)
            "start" -> start(call, reply)
            "current" -> reply.success(holder.current()?.toWire())
            else -> reply.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val sink = MainThreadSink(events)
        collector?.cancel()
        collector =
            scope.launch {
                holder.state.filterNotNull().collect { snapshot ->
                    sink.success(snapshot.toWire())
                    holder.markDelivered(snapshot)
                }
            }
    }

    override fun onCancel(arguments: Any?) {
        collector?.cancel()
        collector = null
    }

    /** Fed by `MainActivity.onRequestPermissionsResult`. Returns whether the request was ours. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST) return false
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        pendingPermissionReplies.forEach { it.success(if (granted) GRANTED else DENIED) }
        pendingPermissionReplies.clear()
        return true
    }

    private fun ensureNotificationPermission(reply: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return reply.success(NOT_REQUIRED)
        val permission = Manifest.permission.POST_NOTIFICATIONS
        if (ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED) {
            return reply.success(GRANTED)
        }
        if (pendingPermissionReplies.isNotEmpty()) {
            pendingPermissionReplies += reply
            return
        }
        // One prompt per process: a denial is remembered, never re-asked.
        if (promptedThisProcess) return reply.success(DENIED)
        val activity = activity() ?: return reply.error(ErrorCodes.NO_ACTIVITY, "No Activity to ask from", null)
        promptedThisProcess = true
        pendingPermissionReplies += reply
        ActivityCompat.requestPermissions(activity, arrayOf(permission), NOTIFICATION_PERMISSION_REQUEST)
    }

    private fun start(call: MethodCall, reply: MethodChannel.Result) {
        val args =
            StartArgs.fromWire(call.arguments)
                ?: return reply.error(
                    ErrorCodes.BAD_ARGUMENTS,
                    "start expects {reference, amountMinor, currency, payee}",
                    null,
                )
        val jobId = "j-${UUID.randomUUID()}"
        if (!holder.tryStart(jobId)) {
            return reply.error(ErrorCodes.ALREADY_RUNNING, "A Payment Job is already running", null)
        }
        try {
            ContextCompat.startForegroundService(context, PaymentJobService.intent(context, jobId, args))
        } catch (e: RuntimeException) {
            // IllegalStateException (incl. ForegroundServiceStartNotAllowedException) or SecurityException.
            holder.abandon(jobId)
            return reply.error(ErrorCodes.SERVICE_START_FAILED, e.message, null)
        }
        reply.success(mapOf("jobId" to jobId))
    }

    private companion object {
        const val NOTIFICATION_PERMISSION_REQUEST = 4202
        const val GRANTED = "granted"
        const val DENIED = "denied"
        const val NOT_REQUIRED = "notRequired"

        @Volatile
        var promptedThisProcess = false
    }
}
