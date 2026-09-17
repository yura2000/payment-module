package dev.test.payment.security

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

/** The six real root signals of docs/architecture.md §8. Not unit-tested: every one touches the device. */
internal object DeviceRootSignals {
    private const val COMMAND_TIMEOUT_MS = 1_000L
    private val SU_DIRECTORIES =
        listOf(
            "/system/bin", "/system/xbin", "/sbin", "/system_ext/bin", "/system/bin/failsafe",
            "/data/local/xbin", "/data/local/bin", "/data/local", "/su/bin",
        )

    fun all(context: Context): List<RootSignal> =
        listOf(
            RootSignal("suBinary") { SU_DIRECTORIES.any { File(it, "su").exists() } },
            RootSignal("whichSu") { runCommand("which", "su").isNotBlank() },
            RootSignal("testKeys") { Build.TAGS?.contains("test-keys") == true },
            RootSignal("dangerousProps") {
                runCommand("getprop", "ro.debuggable").trim() == "1" || runCommand("getprop", "ro.secure").trim() == "0"
            },
            RootSignal("rootPackage") { RootChecks.ROOT_PACKAGES.any { isInstalled(context, it) } },
            RootSignal("writableSystem") {
                File("/proc/mounts").useLines { lines -> lines.any(RootChecks::isWritableSystemMount) }
            },
        )

    private fun isInstalled(context: Context, packageName: String): Boolean =
        try {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }

    /** Runs a short command and returns its output; throws if it does not finish in time. */
    private fun runCommand(vararg command: String): String {
        val process = ProcessBuilder(*command).redirectErrorStream(true).start()
        try {
            if (!process.waitFor(COMMAND_TIMEOUT_MS, TimeUnit.MILLISECONDS)) {
                throw IOException("${command.joinToString(" ")} timed out")
            }
            return process.inputStream.bufferedReader().use { it.readText() }
        } finally {
            // A command that ignores a polite stop must not outlive the check (no-op once it has exited).
            process.destroyForcibly()
        }
    }
}
