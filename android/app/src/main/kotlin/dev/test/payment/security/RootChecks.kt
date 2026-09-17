package dev.test.payment.security

/** One independent root indicator. [fired] may block (disk, process, Binder) and may throw. */
class RootSignal(val name: String, val fired: () -> Boolean)

/** What [RootChecks.run] found: the wire result, plus the signal names for debug logging only. */
data class RootAssessment(
    val result: AssessmentResult,
    val fired: List<String>,
    val failed: List<String>,
)

/**
 * The Rooted Threat Assessment: six hand-rolled signals, `detected` only when at least
 * [THRESHOLD] fire, which absorbs the single-signal false positives documented in
 * docs/research/root-detection.md. A signal that throws could not run: unless the threshold is
 * already met, the result is then `unavailable(error)` — never a silent `clear`
 * (docs/architecture.md §2 principle 8). Blocking — call on `Dispatchers.IO`.
 */
class RootChecks(private val signals: List<RootSignal>) {
    fun run(): RootAssessment {
        val fired = mutableListOf<String>()
        val failed = mutableListOf<String>()
        for (signal in signals) {
            try {
                if (signal.fired()) fired += signal.name
            } catch (e: Exception) {
                failed += signal.name
            }
        }
        val result =
            when {
                fired.size >= THRESHOLD -> AssessmentResult.Detected
                failed.isNotEmpty() -> AssessmentResult.Unavailable(UnavailableReason.ERROR)
                else -> AssessmentResult.Clear
            }
        return RootAssessment(result, fired, failed)
    }

    companion object {
        const val THRESHOLD = 2

        /** Root-manager packages. Each needs a `<queries>` entry in AndroidManifest.xml (targetSdk 36). */
        val ROOT_PACKAGES =
            listOf(
                "com.topjohnwu.magisk",
                "eu.chainfire.supersu",
                "com.noshufou.android.su",
                "com.koushikdutta.superuser",
                "me.weishu.kernelsu",
            )

        private val WRITABLE_CHECK_MOUNT_POINTS = setOf("/system", "/vendor")

        /** Whether one `/proc/mounts` line mounts `/system` or `/vendor` read-write. */
        fun isWritableSystemMount(line: String): Boolean {
            val fields = line.trim().split(Regex("\\s+"))
            if (fields.size < 4) return false
            return fields[1] in WRITABLE_CHECK_MOUNT_POINTS && "rw" in fields[3].split(",")
        }
    }
}
