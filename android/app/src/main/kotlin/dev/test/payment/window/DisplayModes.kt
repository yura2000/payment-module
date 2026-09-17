package dev.test.payment.window

/** One `Display.Mode`, reduced to what the choice needs. */
data class DisplayModeOption(
    val modeId: Int,
    val width: Int,
    val height: Int,
    val refreshRate: Float,
) {
    /** The `preferHighRefreshRate` reply (docs/architecture.md §9). */
    fun toWire(): Map<String, Any?> = mapOf("refreshRate" to refreshRate.toDouble(), "modeId" to modeId)
}

object DisplayModes {
    /** The highest-refresh-rate mode at the current resolution — never a resolution switch. */
    fun highestRefreshRate(
        supported: List<DisplayModeOption>,
        current: DisplayModeOption,
    ): DisplayModeOption? =
        supported
            .filter { it.width == current.width && it.height == current.height }
            .maxByOrNull { it.refreshRate }
}
