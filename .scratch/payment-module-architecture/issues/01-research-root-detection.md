# 01. Root detection approach on Android API 26–36

Type: research
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Which root-detection approach should the Kotlin `SecurityEnvironmentHandler` use on API 26–36, with **no network** (Play Integrity is out of scope)?

Compare hand-rolled heuristics (su binaries on known paths, `ro.build.tags` = test-keys, Magisk/SuperSU/KernelSU packages, `ro.debuggable`, writable system partitions, dangerous props) against the RootBeer library (maintenance status, licence, false-positive record, whether it ships a native lib). Which checks do blocking I/O (they must run on `Dispatchers.IO`)? How do emulators report (the demo video will likely run on one)?

**Deliverable**: recommendation, a Kotlin sketch of the check set, caveats, and what to show on emulator vs real device.

**Decision waiting on this**: ticket 10 (channel contract — payload shape of `assessPosture`: which Threats, any confidence field).

## Answer

**Resolved 2026-09-16 by a research agent.** Findings: `docs/research/root-detection.md` on the throwaway branch `research/root-detection` (`git show research/root-detection:docs/research/root-detection.md`).

**Decision**: hand-roll the check set in `SecurityEnvironmentHandler`; do **not** take the RootBeer dependency.

- Six independent signals: su binary on known paths · `which su` · `Build.TAGS` contains `test-keys` · dangerous props (`ro.debuggable=1` / `ro.secure=0` via `getprop`) · known root-manager packages (Magisk, SuperSU, KernelSU, classic su managers) · writable `/system` or `/vendor` in `/proc/mounts`.
- Report `Threat.ROOTED` only when **≥ 2 signals** fire. Rationale: RootBeer's `isRooted()` ORs everything and its own tracker documents recurring single-signal false positives (dangerous props on LineageOS/custom ROMs, busybox on OEM stock ROMs, RW-system vs systemless root). Accepted trade-off: a hidden Magisk (repackaged app + DenyList) can drop to 0–1 signals → "Secure". Best-effort signal, not a security boundary; Play Integrity is the real attestation and is out of scope.
- Everything except `Build.TAGS` blocks (disk `stat`, process exec, Binder to `PackageManager`) → run the whole `collectThreats()` in `withContext(Dispatchers.IO)`, hop to `Dispatchers.Main` for `result.success`. Process execs get a 1 s timeout + `destroyForcibly()`.
- **targetSdk 36 gate**: `PackageManager.getPackageInfo` is filtered by package visibility (API 30+); every package name checked needs a `<queries><package android:name=…/></queries>` manifest entry or the check silently reports "not installed".
- RootBeer facts for the spec's "rejected alternatives": Apache-2.0, v0.1.2 (2026-03) on Maven Central, ships a native `.so` (16 KB-page-safe only from 0.1.2), no emulator awareness.

**Demo guidance** (added to the map Notes): Google APIs / AOSP AVD images are pre-rooted and test-key-signed by design → they *legitimately* report Compromised. Use a **Google Play** system image or a real unrooted device for the Secure path; say on camera that a rooted AVD is intentional when showing the Compromised path.

**Downstream**: ticket 10 (channel contract) must decide whether `assessPosture` returns only `{posture, threats}` or also a diagnostic `signals: [...]` array — the agent left this open on purpose (product/API-surface call). Added to ticket 10.

**Review notes on the Kotlin sketch** (don't copy blindly): `hasTestKeys()` needs no I/O and can stay out of the IO batch; the `/proc/mounts` parser assumes the 4th field is the options list (true for that file) — keep it, but cover it with a unit test; KernelSU's manager `applicationId` is build-configurable, so `me.weishu.kernelsu` is a default, not a guarantee.
