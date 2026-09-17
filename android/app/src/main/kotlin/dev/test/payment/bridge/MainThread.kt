package dev.test.payment.bridge

import android.os.Handler
import android.os.Looper

/**
 * The Android main thread, behind an interface so [MainThreadResult] and [MainThreadSink] can be
 * unit-tested on the JVM, where there is no Looper.
 */
interface MainThread {
    val isCurrent: Boolean

    fun post(block: () -> Unit)
}

object AndroidMainThread : MainThread {
    private val handler by lazy { Handler(Looper.getMainLooper()) }

    override val isCurrent: Boolean
        get() = Looper.myLooper() == Looper.getMainLooper()

    override fun post(block: () -> Unit) {
        handler.post(block)
    }
}

/** Runs [block] inline when already on the main thread, otherwise posts it there. */
internal fun MainThread.execute(block: () -> Unit) {
    if (isCurrent) block() else post(block)
}
