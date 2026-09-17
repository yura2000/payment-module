package dev.test.payment.window

import android.app.Activity
import android.view.Display
import android.view.WindowManager
import androidx.core.content.ContextCompat
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.ErrorCodes
import dev.test.payment.bridge.MainThreadResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `window` (docs/architecture.md §9, §11, §12.2). Stateless: Dart owns the Secure Window's
 * lifetime and re-asserts it on resume, so this only adds or clears `FLAG_SECURE`.
 */
class WindowHandler(private val activity: () -> Activity?) : ChannelHandler, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, ChannelNames.WINDOW).also { it.setMethodCallHandler(this) }
    }

    override fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "setSecure" -> setSecure(call, reply)
            "preferHighRefreshRate" -> preferHighRefreshRate(reply)
            else -> reply.notImplemented()
        }
    }

    private fun setSecure(call: MethodCall, reply: MethodChannel.Result) {
        val secure =
            (call.arguments as? Map<*, *>)?.get("secure") as? Boolean
                ?: return reply.error(ErrorCodes.BAD_ARGUMENTS, "setSecure expects {secure: bool}", null)
        val window = activity()?.window ?: return reply.error(ErrorCodes.NO_ACTIVITY, "No Activity attached", null)
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        reply.success(null)
    }

    private fun preferHighRefreshRate(reply: MethodChannel.Result) {
        val activity = activity() ?: return reply.error(ErrorCodes.NO_ACTIVITY, "No Activity attached", null)
        val display = ContextCompat.getDisplayOrDefault(activity)
        val choice =
            DisplayModes.highestRefreshRate(
                supported = display.supportedModes.map { it.toOption() },
                current = display.mode.toOption(),
            ) ?: return reply.success(null)
        val window = activity.window
        window.attributes = window.attributes.apply { preferredDisplayModeId = choice.modeId }
        reply.success(choice.toWire())
    }

    private fun Display.Mode.toOption() = DisplayModeOption(modeId, physicalWidth, physicalHeight, refreshRate)
}
