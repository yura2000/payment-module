package dev.test.payment

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File

/**
 * Reads contract/fixtures/<name>.json — the same files the Dart contract tests read — into plain
 * Kotlin values, numbers widened to Long/Double so they compare equal to a channel payload after
 * [normalized].
 */
object ContractFixtures {
    private val directory = File(System.getProperty("contract.fixtures") ?: error("Run through Gradle: contract.fixtures is unset"))

    fun load(name: String): Any? = Json.parseToJsonElement(File(directory, "$name.json").readText()).toPlain()

    /** Widens Int→Long and Float→Double throughout, so a payload map compares equal to [load]'s output. */
    fun normalized(value: Any?): Any? =
        when (value) {
            is Int -> value.toLong()
            is Float -> value.toDouble()
            is Map<*, *> -> value.entries.associate { (key, item) -> key to normalized(item) }
            is List<*> -> value.map(::normalized)
            else -> value
        }

    private fun JsonElement.toPlain(): Any? =
        when (this) {
            JsonNull -> null
            is JsonObject -> entries.associate { (key, item) -> key to item.toPlain() }
            is JsonArray -> map { it.toPlain() }
            is JsonPrimitive ->
                if (isString) content else content.toBooleanStrictOrNull() ?: content.toLongOrNull() ?: content.toDouble()
        }
}
