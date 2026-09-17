package dev.test.payment.payment

import android.content.Intent

/** The `start` arguments (docs/architecture.md §9), also carried to the service as Intent extras. */
data class StartArgs(
    val reference: String,
    val amountMinor: Long,
    val currency: String,
    val payee: String,
) {
    fun writeTo(intent: Intent): Intent =
        intent
            .putExtra(EXTRA_REFERENCE, reference)
            .putExtra(EXTRA_AMOUNT_MINOR, amountMinor)
            .putExtra(EXTRA_CURRENCY, currency)
            .putExtra(EXTRA_PAYEE, payee)

    companion object {
        private const val EXTRA_REFERENCE = "dev.test.payment.extra.REFERENCE"
        private const val EXTRA_AMOUNT_MINOR = "dev.test.payment.extra.AMOUNT_MINOR"
        private const val EXTRA_CURRENCY = "dev.test.payment.extra.CURRENCY"
        private const val EXTRA_PAYEE = "dev.test.payment.extra.PAYEE"

        /** `null` unless [arguments] is a map with all four fields of the right types. */
        fun fromWire(arguments: Any?): StartArgs? {
            val map = arguments as? Map<*, *> ?: return null
            return StartArgs(
                reference = map["reference"] as? String ?: return null,
                // The codec sends a Dart int as Integer or Long depending on its magnitude.
                amountMinor = (map["amountMinor"] as? Number)?.toLong() ?: return null,
                currency = map["currency"] as? String ?: return null,
                payee = map["payee"] as? String ?: return null,
            )
        }

        fun readFrom(intent: Intent): StartArgs? {
            if (!intent.hasExtra(EXTRA_AMOUNT_MINOR)) return null
            return StartArgs(
                reference = intent.getStringExtra(EXTRA_REFERENCE) ?: return null,
                amountMinor = intent.getLongExtra(EXTRA_AMOUNT_MINOR, 0),
                currency = intent.getStringExtra(EXTRA_CURRENCY) ?: return null,
                payee = intent.getStringExtra(EXTRA_PAYEE) ?: return null,
            )
        }
    }
}
