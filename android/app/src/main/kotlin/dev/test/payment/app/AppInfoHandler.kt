package dev.test.payment.app

import android.content.Context
import android.os.Build
import dev.test.payment.BuildConfig
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.MainThreadResult
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The `buildInfo` reply: what the Dart bootstrap compares with its `BRAND` dart-define. */
data class BuildInfo(
    val flavor: String,
    val applicationId: String,
    val versionName: String,
    val versionCode: Int,
    val sdkInt: Int,
) {
    fun toWire(): Map<String, Any?> =
        mapOf(
            "flavor" to flavor,
            "applicationId" to applicationId,
            "versionName" to versionName,
            "versionCode" to versionCode,
            "sdkInt" to sdkInt,
        )
}

/** `app` (docs/architecture.md §6, §9). */
class AppInfoHandler(private val context: Context) : ChannelHandler, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    override fun attach(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, ChannelNames.APP).also { it.setMethodCallHandler(this) }
    }

    override fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "buildInfo" ->
                reply.success(
                    BuildInfo(
                        flavor = BuildConfig.FLAVOR,
                        applicationId = context.packageName,
                        versionName = BuildConfig.VERSION_NAME,
                        versionCode = BuildConfig.VERSION_CODE,
                        sdkInt = Build.VERSION.SDK_INT,
                    ).toWire(),
                )
            else -> reply.notImplemented()
        }
    }
}
