# Payment Confirmation Module

A white-label Payment Confirmation Module: one codebase that ships one Brand per Flavor, confirms a Payment on a Secure Window, and runs the (simulated) Payment Job in an Android foreground service.

## Language

### Branding

**Brand**:
A white-label identity: palette, shape, density, motion, copy and functional toggles. The unit the whole UI is configured by.
_Avoid_: tenant, theme (a theme is only the visual part of a Brand), skin

**Flavor**:
The build configuration that ships exactly one Brand and is named after it. There is no runtime Brand switching.
_Avoid_: build config, variant, target

**Retail**:
The Brand the task calls "Brand A (Retail Shop)": warm palette, rounded, fluid, shows the Promo Banner.
_Avoid_: Brand A

**Utility**:
The Brand the task calls "Brand B (Utility Pay)": navy/slate palette, dense, sharp, shows the Bill Breakdown.
_Avoid_: Brand B

**Promo Banner**:
Retail's brand feature: a promotional banner on the payment screen. Purely visual; never changes the amount.

**Bill Breakdown**:
Utility's brand feature: an itemised view of the Payment's Line Items.

**Section**:
A building block of the payment screen that a Brand orders: the summary, the Promo Banner, the Bill Breakdown, the pay button, or a section the Brand supplies itself.
_Avoid_: slot, block, widget

**Brand Token**:
A visual or motion value a Brand supplies: palette seed and accent, corner radius, density, spacing, the minimum Security Scan duration.
_Avoid_: theme value, style, design token

### Payment

**Payment**:
The transaction awaiting confirmation: amount, currency, payee and Line Items.
_Avoid_: order, bill, invoice, transaction

**Line Item**:
One priced component of a Payment. Every Brand's Payment has them; only some Brands show them.

**Payment Job**:
The simulated processing of a confirmed Payment, run by the Android foreground service and reporting progress until it succeeds or fails. It cannot be cancelled.
_Avoid_: task, background process, transaction

**Receipt**:
Proof of a succeeded Payment Job: a reference and the completion time.
_Avoid_: confirmation, transaction id

**Payment Failure**:
Why a Payment Job failed: declined, timed out, or the processor was unavailable. A failed Payment may be retried from the same screen.
_Avoid_: error (that word is for unexpected faults)

**Result View**:
What the payment screen shows once the Payment Job has completed. It is a state of the same screen, never a separate page, and stays a Secure Window until the user leaves.
_Avoid_: result page, success screen

### Security

**Security Posture**:
The outcome of assessing the device environment, one Threat Assessment per kind of Threat. Classified Secure (every check clear), Compromised (any Threat detected) or Unverified (no Threat detected, but at least one check could not run on this device).
_Avoid_: security status, environment check result, unknown (say Unverified)

**Threat Assessment**:
The result of checking for one kind of Threat: detected, clear, or unavailable when the check cannot run (unsupported Android version, or the check itself failed).
_Avoid_: check result, signal

**Threat**:
A detected condition that compromises the Security Posture: a rooted device, or an active screen recorder.
_Avoid_: risk, issue, violation

**Security Scan**:
The phase, shown as an animation, during which the first Security Posture is assessed; it lasts at least the Brand's minimum scan duration. Happens once when the payment screen opens; later re-assessments (on resume, or when a screen recorder starts or stops) are silent.
_Avoid_: security check, re-scan, scanning animation (that is the visual, not the phase)

**Posture Policy**:
A Brand's rule, per kind of Threat, for what a detected Threat does to the payment (block it, or warn and allow it) and what an unavailable check does (allow silently, or allow with a notice).

**Policy Verdict**:
The result of applying the Posture Policy to a Security Posture: which Threats block the payment, which only warn, and which checks deserve a notice.
_Avoid_: decision, permission

**Secure Window**:
The state in which the Android window refuses screenshots and screen sharing. Held for as long as a payment screen is visible.
_Avoid_: window protection, secure flag
