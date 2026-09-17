package dev.test.payment.bridge

import android.app.Activity
import android.content.Context
import dev.test.payment.app.AppInfoHandler
import dev.test.payment.payment.PaymentJobHandler
import dev.test.payment.security.SecurityEnvironmentHandler
import dev.test.payment.window.WindowHandler
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

/**
 * Owns the four channel handlers and the coroutine scope their work runs in, for one Flutter
 * engine. `MainActivity` delegates to exactly [register], [dispose] and [onPermissionResult]
 * (docs/architecture.md §9).
 */
class ChannelRegistry(context: Context, activity: () -> Activity?) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val paymentJob = PaymentJobHandler(context, activity, scope)
    private val handlers: List<ChannelHandler> =
        listOf(
            SecurityEnvironmentHandler(context, scope),
            WindowHandler(activity),
            paymentJob,
            AppInfoHandler(context),
        )

    fun register(messenger: BinaryMessenger) = handlers.forEach { it.attach(messenger) }

    fun dispose() {
        handlers.forEach { it.detach() }
        scope.cancel()
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean =
        paymentJob.onPermissionResult(requestCode, grantResults)
}
