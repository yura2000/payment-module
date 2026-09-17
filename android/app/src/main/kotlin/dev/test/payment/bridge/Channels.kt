package dev.test.payment.bridge

import io.flutter.plugin.common.BinaryMessenger

/**
 * The six channel names of docs/architecture.md §9 (ADR-0003: four method channels, two event
 * channels). Pinned against contract/fixtures/channels.json by a JVM test; the Dart side pins the
 * same file.
 */
object ChannelNames {
    private const val PREFIX = "dev.test.payment"
    const val SECURITY_ENVIRONMENT = "$PREFIX/security.environment"
    const val SECURITY_ENVIRONMENT_EVENTS = "$PREFIX/security.environment/events"
    const val WINDOW = "$PREFIX/window"
    const val PAYMENT_JOB = "$PREFIX/payment.job"
    const val PAYMENT_JOB_EVENTS = "$PREFIX/payment.job/events"
    const val APP = "$PREFIX/app"
}

/** The error codes of docs/architecture.md §9. */
object ErrorCodes {
    const val BAD_ARGUMENTS = "badArguments"
    const val NO_ACTIVITY = "noActivity"
    const val ALREADY_RUNNING = "alreadyRunning"
    const val SERVICE_START_FAILED = "serviceStartFailed"
}

/** One concern's channels (method + optional event channel), attached for one engine's lifetime. */
interface ChannelHandler {
    fun attach(messenger: BinaryMessenger)

    fun detach()
}
