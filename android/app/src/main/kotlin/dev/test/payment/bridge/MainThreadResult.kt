package dev.test.payment.bridge

import io.flutter.plugin.common.MethodChannel

/**
 * A [MethodChannel.Result] that always replies on the main thread — the threading guarantee of
 * docs/architecture.md §9, enforced here rather than by discipline at every call site.
 */
class MainThreadResult(
    private val delegate: MethodChannel.Result,
    private val mainThread: MainThread = AndroidMainThread,
) : MethodChannel.Result {
    override fun success(result: Any?) = mainThread.execute { delegate.success(result) }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) =
        mainThread.execute { delegate.error(errorCode, errorMessage, errorDetails) }

    override fun notImplemented() = mainThread.execute { delegate.notImplemented() }
}
