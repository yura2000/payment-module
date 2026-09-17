package dev.test.payment.security

import android.content.Context
import android.util.Log
import dev.test.payment.bridge.ChannelHandler
import dev.test.payment.bridge.ChannelNames
import dev.test.payment.bridge.MainThreadResult
import dev.test.payment.bridge.MainThreadSink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * `security.environment` + `security.environment/events` (docs/architecture.md §8, §9).
 *
 * `assess` acks as soon as an assessment is running — a new one, or the one already in progress
 * (concurrent calls coalesce); the snapshot follows on the event stream, the single source of
 * truth. The stream is replay-1. Listening registers the API 35+ recorder callback and cancelling
 * unregisters it, so the callback lives exactly as long as the observing screen's subscription.
 * A snapshot is only published once both halves are known: the first root assessment, and the
 * recorder state (fixed `unavailable(apiLevel)` below API 35). All state is touched on the main
 * thread only — `scope` runs on `Dispatchers.Main.immediate`.
 */
class SecurityEnvironmentHandler(
    context: Context,
    private val scope: CoroutineScope,
    private val rootChecks: RootChecks = RootChecks(DeviceRootSignals.all(context)),
) : ChannelHandler, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val recordingMonitor = ScreenRecordingMonitor.create(context, ::onRecordingChanged)

    // Registration calls run one at a time, in order, so listen → cancel → listen can't interleave.
    private val monitorDispatcher = Dispatchers.IO.limitedParallelism(1)

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var sink: EventChannel.EventSink? = null
    private var listening = false
    private var assessment: Job? = null
    private var rooted: AssessmentResult? = null
    private var screenRecording: AssessmentResult? =
        if (recordingMonitor == null) AssessmentResult.Unavailable(UnavailableReason.API_LEVEL) else null
    private var lastSnapshot: PostureSnapshot? = null

    override fun attach(messenger: BinaryMessenger) {
        methodChannel = MethodChannel(messenger, ChannelNames.SECURITY_ENVIRONMENT).also { it.setMethodCallHandler(this) }
        eventChannel = EventChannel(messenger, ChannelNames.SECURITY_ENVIRONMENT_EVENTS).also { it.setStreamHandler(this) }
    }

    @OptIn(DelicateCoroutinesApi::class)
    override fun detach() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        sink = null
        listening = false
        // The engine's scope is being cancelled; the unregister call must still run.
        recordingMonitor?.let { monitor -> GlobalScope.launch(monitorDispatcher) { monitor.stop() } }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val reply = MainThreadResult(result)
        when (call.method) {
            "assess" -> {
                assess()
                reply.success(null)
            }
            else -> reply.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val mainSink = MainThreadSink(events)
        sink = mainSink
        listening = true
        lastSnapshot?.let { mainSink.success(it.toWire()) }
        val monitor = recordingMonitor ?: return
        scope.launch {
            val recording = withContext(monitorDispatcher) { runCatching { monitor.start() } }
            if (!listening) return@launch
            screenRecording =
                recording.fold(
                    onSuccess = { if (it) AssessmentResult.Detected else AssessmentResult.Clear },
                    onFailure = { AssessmentResult.Unavailable(UnavailableReason.ERROR) },
                )
            publish()
        }
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        listening = false
        val monitor = recordingMonitor ?: return
        screenRecording = null
        scope.launch(monitorDispatcher) { runCatching { monitor.stop() } }
    }

    private fun assess() {
        if (assessment?.isActive == true) return
        assessment =
            scope.launch {
                val outcome = withContext(Dispatchers.IO) { rootChecks.run() }
                if (outcome.fired.isNotEmpty() || outcome.failed.isNotEmpty()) {
                    Log.d(TAG, "Root signals fired=${outcome.fired} failed=${outcome.failed}")
                }
                rooted = outcome.result
                publish()
            }
    }

    private fun onRecordingChanged(recording: Boolean) {
        if (!listening) return
        screenRecording = if (recording) AssessmentResult.Detected else AssessmentResult.Clear
        publish()
    }

    private fun publish() {
        val snapshot =
            PostureSnapshot(
                rooted = rooted ?: return,
                screenRecording = screenRecording ?: return,
                assessedAt = System.currentTimeMillis(),
            )
        lastSnapshot = snapshot
        sink?.success(snapshot.toWire())
    }

    private companion object {
        const val TAG = "SecurityEnvironment"
    }
}
