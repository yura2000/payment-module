package dev.test.payment.security

import android.content.Context
import android.os.Build
import android.view.WindowManager
import androidx.annotation.RequiresApi
import androidx.annotation.WorkerThread
import androidx.core.content.ContextCompat
import java.util.function.Consumer

/**
 * The API 35+ screen-recording signal (`WindowManager.addScreenRecordingCallback`). Both calls
 * are blocking Binder round-trips — call them off the main thread. Changes are delivered on the
 * main thread (docs/architecture.md §8).
 */
interface ScreenRecordingMonitor {
    /** Registers the callback and returns whether this app is being recorded right now. */
    @WorkerThread
    fun start(): Boolean

    @WorkerThread
    fun stop()

    companion object {
        /** `null` below API 35, where there is no official signal. */
        fun create(context: Context, onChange: (recording: Boolean) -> Unit): ScreenRecordingMonitor? =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                Api35ScreenRecordingMonitor(context, onChange)
            } else {
                null
            }
    }
}

@RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)
private class Api35ScreenRecordingMonitor(
    context: Context,
    onChange: (Boolean) -> Unit,
) : ScreenRecordingMonitor {
    private val windowManager = context.getSystemService(WindowManager::class.java)
    private val mainExecutor = ContextCompat.getMainExecutor(context)
    private val callback =
        Consumer<Int> { state -> onChange(state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE) }
    private var registered = false

    @Synchronized
    override fun start(): Boolean {
        if (registered) windowManager.removeScreenRecordingCallback(callback)
        val state = windowManager.addScreenRecordingCallback(mainExecutor, callback)
        registered = true
        return state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
    }

    @Synchronized
    override fun stop() {
        if (!registered) return
        windowManager.removeScreenRecordingCallback(callback)
        registered = false
    }
}
