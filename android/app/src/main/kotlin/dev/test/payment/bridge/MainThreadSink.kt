package dev.test.payment.bridge

import io.flutter.plugin.common.EventChannel

/**
 * An [EventChannel.EventSink] that always emits on the main thread — the event-stream half of the
 * threading guarantee in docs/architecture.md §9.
 */
class MainThreadSink(
    private val delegate: EventChannel.EventSink,
    private val mainThread: MainThread = AndroidMainThread,
) : EventChannel.EventSink {
    override fun success(event: Any?) = mainThread.execute { delegate.success(event) }

    override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) =
        mainThread.execute { delegate.error(errorCode, errorMessage, errorDetails) }

    override fun endOfStream() = mainThread.execute { delegate.endOfStream() }
}
