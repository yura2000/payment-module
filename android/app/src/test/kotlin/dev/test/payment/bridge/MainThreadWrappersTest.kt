package dev.test.payment.bridge

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test

class MainThreadWrappersTest {
    private class FakeMainThread(override var isCurrent: Boolean) : MainThread {
        val posted = mutableListOf<() -> Unit>()

        override fun post(block: () -> Unit) {
            posted += block
        }

        fun drain() {
            posted.toList().forEach { it() }
            posted.clear()
        }
    }

    private class RecordingResult : MethodChannel.Result {
        val calls = mutableListOf<String>()

        override fun success(result: Any?) {
            calls += "success($result)"
        }

        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            calls += "error($errorCode)"
        }

        override fun notImplemented() {
            calls += "notImplemented"
        }
    }

    private class RecordingSink : EventChannel.EventSink {
        val calls = mutableListOf<String>()

        override fun success(event: Any?) {
            calls += "success($event)"
        }

        override fun error(errorCode: String?, errorMessage: String?, errorDetails: Any?) {
            calls += "error($errorCode)"
        }

        override fun endOfStream() {
            calls += "endOfStream"
        }
    }

    @Test
    fun `result replies inline when already on the main thread`() {
        val delegate = RecordingResult()
        val result = MainThreadResult(delegate, FakeMainThread(isCurrent = true))

        result.success(1)
        result.error("noActivity", null, null)
        result.notImplemented()

        assertEquals(listOf("success(1)", "error(noActivity)", "notImplemented"), delegate.calls)
    }

    @Test
    fun `result posts to the main thread when called from another thread`() {
        val delegate = RecordingResult()
        val mainThread = FakeMainThread(isCurrent = false)
        val result = MainThreadResult(delegate, mainThread)

        result.success("x")
        assertEquals(emptyList<String>(), delegate.calls)

        mainThread.drain()
        assertEquals(listOf("success(x)"), delegate.calls)
    }

    @Test
    fun `sink emits inline on the main thread and posts otherwise`() {
        val delegate = RecordingSink()
        val mainThread = FakeMainThread(isCurrent = true)
        val sink = MainThreadSink(delegate, mainThread)

        sink.success("a")
        mainThread.isCurrent = false
        sink.success("b")
        sink.endOfStream()
        assertEquals(listOf("success(a)"), delegate.calls)

        mainThread.drain()
        assertEquals(listOf("success(a)", "success(b)", "endOfStream"), delegate.calls)
    }
}
