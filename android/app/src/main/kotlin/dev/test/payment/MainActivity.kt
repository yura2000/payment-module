package dev.test.payment

import dev.test.payment.bridge.ChannelRegistry
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var channels: ChannelRegistry? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channels =
            ChannelRegistry(applicationContext) { takeUnless { it.isFinishing || it.isDestroyed } }
                .also { it.register(flutterEngine.dartExecutor.binaryMessenger) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        channels?.dispose()
        channels = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        channels?.onPermissionResult(requestCode, grantResults)
    }
}
