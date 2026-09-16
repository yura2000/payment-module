---
status: accepted
date: 2026-09-16
---
# Android is the only platform; there are no "unsupported platform" fallback adapters

The native ports (`SecurityEnvironment`, `SecureWindow`, `PaymentProcessor`) have exactly two adapters each: the Kotlin-backed channel adapter for production and a scripted fake for tests (`test/support/fakes/`). There is deliberately no iOS implementation and no no-op adapter that lets the app run on an unsupported platform — the task is Android-only, and a silent no-op would let a payment flow run with no security posture at all. The constraint is not visible in the code, which is why it is recorded here: a future reader adding an iOS target should add real adapters, not relax the ports.
