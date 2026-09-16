# Root detection approach on Android API 26–36 (no network)

## Question

Which root-detection approach should a Kotlin `SecurityEnvironmentHandler` (a MethodChannel handler) use on
API 26–36, with no network available (Play Integrity is out of scope)? Compare hand-rolled heuristics against
the RootBeer library (maintenance, licence, false-positive record, native lib). Identify which checks block
(must run on `Dispatchers.IO`) and how Android emulators/AVDs report under each approach.

## Short answer

Build a small, in-repo check set (su paths + `which su`, `Build.TAGS` test-keys, dangerous props via `getprop`,
writable `/system` via `mount`, known root-app packages) instead of taking a RootBeer dependency. RootBeer is
still maintained and Apache-2.0, but its own issue tracker documents recurring false positives on custom ROMs
and some OEM stock ROMs from exactly the checks we need, and it has zero emulator-vs-real-root differentiation.
Every filesystem/process/PackageManager check is blocking (`Dispatchers.IO`); reading `Build.TAGS`/`HARDWARE`/
`FINGERPRINT` is a free in-memory field read. `targetSdk 36` requires `<queries>` manifest entries for any
package-name lookup (Magisk/SuperSU/KernelSU) or it silently reports "not installed." Standard Android Studio
"Google APIs"/AOSP emulator images ship pre-rooted and debuggable by design, so any of these approaches will
correctly-but-confusingly report Compromised on them; use a "Google Play" system image (or a real device) for
a Secure demo.

## Findings

### 1. Hand-rolled heuristics — mechanism, API notes, blocking behaviour

| Check | How it works | Blocking? | API-level notes |
|---|---|---|---|
| su on known paths | `File(path, "su").exists()` over a path list | Yes — `stat()` per path, disk I/O | No official API; path lists are community-sourced. RootBeer's list (15 dirs, including `/system_ext/bin` added for newer partition layouts) is a reasonable reference set — [Const.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/Const.java) |
| `which su` | `ProcessBuilder("which","su")`, read stdout | Yes — process fork/exec + stream read, can hang without a timeout | Same technique RootBeer uses (`checkSuExists`) — [RootBeer.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/RootBeer.java) |
| `ro.build.tags == test-keys` | Read `android.os.Build.TAGS` | **No** — `static final` field populated once via `SystemProperties.get("ro.build.tags")` at class-load; later reads are plain memory reads | Confirmed in AOSP source: `public static final String TAGS = getString("ro.build.tags");` with Javadoc "Comma-separated tags describing the build, like `unsigned,debug`" — [Build.java, android.googlesource.com](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/Build.java). Production/`release-keys` signing is the AOSP norm; test-keys are the standard AOSP dev-signing keys and "should never be used for production devices" — [Sign builds for release, source.android.com](https://source.android.com/docs/core/ota/sign_builds) |
| Magisk / SuperSU / KernelSU package presence | `PackageManager.getPackageInfo(pkg, 0)` per known package name | Yes — Binder IPC to `system_server` / package db | **API 30+ gate**: package-visibility filtering applies to `getPackageInfo()` lookups; an undeclared package name is filtered out (behaves as not-installed) unless it is one of a short list of automatically-visible packages (installer, signature-matching apps, apps you already interact with via services/providers/IME) — root-management apps do **not** qualify. You must add a `<queries><package android:name="..."/></queries>` entry per package you want to detect — [Package visibility filtering](https://developer.android.com/training/package-visibility), [Automatic visibility](https://developer.android.com/training/package-visibility/automatic). `targetSdk 36` is well past this gate, so this applies in full. |
| `ro.debuggable`, `ro.secure` ("dangerous props") | Spawn `getprop`, parse output for `[ro.debuggable]: [1]` / `[ro.secure]: [0]` | Yes — process exec, same cost profile as `which su` | This is exactly RootBeer's `checkForDangerousProps` (`propsReader()` → `Runtime.exec("getprop")`) — [RootBeer.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/RootBeer.java). Reflection into the hidden `android.os.SystemProperties.get()` is faster (no process spawn) but is a non-SDK interface with no compatibility guarantee; prefer the `getprop` exec RootBeer uses, or accept the process-spawn cost since it's already off the main thread. |
| Writable system partitions | Spawn `mount`, or read `/proc/mounts`, check `rw` flag on `/system`, `/vendor`, `/sbin`, `/etc`, etc. | Yes — process exec or file read | Weak on modern devices: systemless root (Magisk, KernelSU) doesn't need `/system` writable at all — RootBeer's own docs flag this: "Some newer root methods do not require RW access to the `/system` partition (e.g., systemless root)" — [README.md](https://raw.githubusercontent.com/scottyab/rootbeer/master/README.md) |

KernelSU is architecturally different from Magisk/SuperSU: it is kernel-mode (a patched kernel / kernel module),
and mounts module changes through a "metamodule" system rather than writing `/system` directly — closer to
Magisk's systemless approach than to classic su-on-disk rooting — [What is KernelSU](https://kernelsu.org/guide/what-is-kernelsu.html),
[Difference with Magisk](https://kernelsu.org/guide/difference-with-magisk.html). Its manager app's build config
sets `namespace = "me.weishu.kernelsu"` with the actual `applicationId` driven by a Gradle property (so it can be
rebranded in forks/custom builds) — [manager/app/build.gradle.kts, tiann/KernelSU](https://raw.githubusercontent.com/tiann/KernelSU/main/manager/app/build.gradle.kts).
Practical effect: su-path and RW-partition checks are weak signals against KernelSU/modern Magisk; package-name
and `su`-reachability checks remain the most direct signal, with the same evadability caveat as below.

Magisk itself ships hiding: Zygisk's **DenyList** (with companion modules like Shamiko) can hide the Magisk app
and `su` from a chosen app's process, so package-name and binary-path checks are not reliable against a
motivated attacker — this is widely documented community/security-research material, not an AOSP or Magisk
first-party doc page, so treat it as corroborated-but-UNVERIFIED against a primary source.

### 2. RootBeer (github.com/scottyab/rootbeer)

- **Licence**: Apache License 2.0, `Copyright (C) 2015, Scott Alexander-Bown, Mat Rollings` — [README.md § Licence](https://raw.githubusercontent.com/scottyab/rootbeer/master/README.md).
- **Maintenance status**: not archived; repo last pushed 2026-03-17, 51 open issues, ~2.9k stars — [repo metadata via GitHub API](https://api.github.com/repos/scottyab/rootbeer). Release cadence is slow but non-zero: `0.0.8` (2020-02-08) → `0.0.9` (2021-05-04) → `0.1.0` (2021-05-24) → `0.1.1` (2024-09-18) → `0.1.2` (2026-03-07) — [Releases](https://github.com/scottyab/rootbeer/releases). **Latest release, `0.1.2`, is published on Maven Central** — confirmed directly against the authoritative index: `<latest>0.1.2</latest>`, `<release>0.1.2</release>`, synced 2026-03-17 — [maven-metadata.xml, repo1.maven.org](https://repo1.maven.org/maven2/com/scottyab/rootbeer-lib/maven-metadata.xml). (A `search.maven.org` query during this research still showed `0.1.1` as newest — that index lags the real repository; don't trust it over `maven-metadata.xml`.)
- **Native library**: yes. A CMake-built shared library (`libtoolChecker.so`, source `toolChecker.cpp`) backs `checkForSuBinary`'s native path; rationale per the README: "Native checks are typically harder to cloak, so some root cloak apps just block the loading of native libraries that contain certain keywords." ABI filters: `armeabi-v7a`, `arm64-v8a`, `x86`, `x86_64` (no riscv64) — [rootbeerlib/build.gradle.kts](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/build.gradle.kts). The `0.1.2` release added `-Wl,-z,max-page-size=16384` and `-DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON`, i.e. **16 KB-page-size alignment** — [CMakeLists.txt](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/cpp/CMakeLists.txt). This matters directly for this project: Google Play requires apps targeting API 35+ (this project targets 36) to support 16 KB pages on 64-bit devices, including bundled third-party native libraries — "If your app uses any prebuilt shared libraries, you must also recompile them in the same way and reimport the 16 KB-aligned libraries," enforcement deadline **2027-02-01** for updates — [Support 16 KB page sizes, developer.android.com](https://developer.android.com/guide/practices/page-sizes) (submission requirement for API 35+ apps began 2025-11-01 per the [Android Developers Blog](https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html), first-party but not developer.android.com itself — treat that specific date as secondary-sourced). Only RootBeer ≥ `0.1.2` is 16 KB-safe.
- **Check set** (Java): `checkRootManagementApps`, `checkPotentiallyDangerousApps`, `checkRootCloakingApps` (all `PackageManager.getPackageInfo` against `Const.java` lists of 12 / 28 / 9 package names respectively), `checkTestKeys` (`Build.TAGS`), `checkForDangerousProps` (`getprop` exec), `checkForBusyBoxBinary` / `checkForSuBinary` (`File.exists()` over `Const.getPaths()`), `checkSuExists` (`which su` exec), `checkForRWSystem` (`mount` exec, parses `rw` flags) — [RootBeer.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/RootBeer.java), [Const.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/Const.java). `isRooted()` ORs all of these except busybox (opt-in via `isRootedWithBusyBoxCheck()`) — no weighting, no threshold, any single signal trips it.
- **The library's own README says to run it off the main thread**: "It is advisable to call `isRooted()` from a background thread as it involves disk I/O" — [README.md § Usage](https://raw.githubusercontent.com/scottyab/rootbeer/master/README.md).
- **False-positive record** is real and current, not historical noise:
  - Busybox left on stock ROMs by OEMs (OnePlus, Moto E, OPPO R9m) — library's own README, which is why busybox was removed from the default `isRooted()` path.
  - `checkForRWSystem` explicitly acknowledged as bypassable by systemless root (README, "Limitations" table).
  - [Issue #181](https://github.com/scottyab/rootbeer/issues/181), open since 2021-08: `checkForDangerousProps` false-triggers on non-rooted LineageOS/custom-ROM devices (Fairphone, OnePlus running LineageOS); still open with no fix as of this research.
  - [Issue #226](https://github.com/scottyab/rootbeer/issues/226) (closed 2024-09 by the maintainer as a "rant," but the underlying reports are concrete): NJTransit's Play Store reviews full of false-positive lockouts, a French-bank and a Danish mobile-payments app (MobilePay) reportedly affected, "all BlackView 8000 phones" flagged, a report of "flagging all Unix sockets that are 32 bytes long." Maintainer's reply: "I appreciate it can be frustrating... this is an indication of root and not to treat the result of the rootbeer check as 100% truth."
  - The README itself states the disclaimer plainly: "root==god, so there's no 100% guaranteed way to check for root" and points to Google Play Integrity API as "a more robust solution" (out of scope here per the ticket) and links to a published bypass write-up.
- **Emulator handling**: none. There is no `isEmulator`/emulator-aware method anywhere in the public API (confirmed by the full method inventory above). The README explicitly pairs test-keys with emulators — `checkTestKeys`: "Verifies if the device's firmware is signed with Android's test keys, which it would be on AOSP or certain emulators" — meaning RootBeer expects and accepts that emulators will trip this check. The README's own "Other libraries" section points to a *separate* anti-emulator project (Tim Strazzere's) as the tool for that distinct concern, underscoring that RootBeer intentionally does not attempt it.

### 3. Blocking-I/O summary

| Operation | Blocking? | Why |
|---|---|---|
| `File.exists()` (su paths, RW paths) | Yes | disk `stat()` |
| `ProcessBuilder`/`Runtime.exec` (`which`, `getprop`, `mount`) | Yes, and can hang | process fork/exec + pipe read; give it an explicit timeout and `destroyForcibly()` on timeout |
| `PackageManager.getPackageInfo()` | Yes | Binder IPC to `system_server`, backed by the package database |
| `System.loadLibrary()` (RootBeer's native check) | Yes on first call | `dlopen` reads the `.so` from the APK/extracted-lib dir; cached after |
| `Build.TAGS` / `Build.HARDWARE` / `Build.FINGERPRINT` | **No** | `static final` fields resolved once at class-load from `SystemProperties.get()` — [Build.java](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/Build.java) |

Android's own ANR guidance backs the general pattern already decided for this project: "Don't perform blocking
or long-running operations on the app's main thread... use `withContext(Dispatchers.IO)`," with a 5-second
input-dispatch timeout as the hard ANR trigger — [Keep your app responsive, developer.android.com](https://developer.android.com/topic/performance/anrs/keep-your-app-responsive).
`Dispatchers.IO` itself is documented as "designed for offloading blocking IO tasks to a shared pool of threads,"
sized to `max(64, core count)` by default — [Dispatchers.IO, kotlinlang.org](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-dispatchers/-i-o.html);
Android's coroutines guide gives the same `withContext(Dispatchers.IO) { ... }` main-safety pattern already
adopted for this project — [Improve app performance with Kotlin coroutines](https://developer.android.com/kotlin/coroutines/coroutines-adv).

### 4. Emulator / AVD behaviour (both approaches equally affected)

Android Studio's AVD system images come in meaningfully different flavours for this purpose:

- **"Google Play" images** (the ones with the Play Store icon) are "signed with a release key, which means that
  you can't get elevated privileges (root) with these images" — [Create and manage virtual devices, developer.android.com](https://developer.android.com/studio/run/managing-avds). These behave like a locked production
  device: no `su`, expect `ro.secure=1`.
- **"Google APIs" (no Play Store) and plain AOSP images** are explicitly the ones to use "if you require elevated
  privileges (root) to aid with app troubleshooting" — same page — and support `adb root`/`adb unroot`. These
  ship debuggable and rootable by design.
- Combined with RootBeer's own note that test-keys is expected "on AOSP or certain emulators," a Google
  APIs/AOSP AVD will typically trip su-path, `which su`, dangerous-props, and test-keys checks simultaneously —
  not because anything is wrong, but because that's the documented, intended state of that image type.

**Practical guidance for the demo**: verify which system image the target AVD uses before recording.
- To show the **Secure** path: use a **Google Play** system image (or a real, unrooted, locked-bootloader
  device).
- To show the **Compromised** path: a **Google APIs/AOSP** AVD, or a real rooted test device, both work — but if
  using an AVD, call out on camera that it's an intentionally-rooted developer image, not a "false positive,"
  since the Threat is technically correct for that image's actual state.

## Recommendation

Write the check set directly in `SecurityEnvironmentHandler` rather than adding the RootBeer dependency:

1. It's a small amount of code (six checks, no native build) against RootBeer's public, permissively-licensed
   constant lists reused as reference data — full control over the exact signals fired, without pulling in a
   third-party native `.so` into a payment module's attack surface.
2. Apply a **threshold, not OR-of-all**: require ≥ 2 independent signals before reporting a Threat. This
   directly targets RootBeer's own documented failure mode — single checks (`checkForDangerousProps` on custom
   ROMs, busybox on certain OEM stock ROMs, RW-system against systemless root) firing alone and producing a
   false Compromised result. RootBeer's `isRooted()` cannot do this without being pulled apart into its
   individual per-check calls anyway, at which point most of the "library" benefit is just its constant lists.
3. Keep the package list scoped to actual root brokers (Magisk, SuperSU/Chainfire, KernelSU, common su
   managers) — leave out RootBeer's 28-entry "dangerous apps" list (Lucky Patcher, ROM managers, etc.); that's
   a tampering/piracy signal, not the "rooted device" Threat this handler is scoped to.
4. Declare a `<queries>` block for every package name checked — required for `targetSdk 36`, otherwise the
   check silently always returns false.
5. Run the whole `collectThreats()` set inside `withContext(Dispatchers.IO)`, hop back to `Dispatchers.Main`
   only to touch `result.success(...)`, per the project's existing MethodChannel convention.

RootBeer is a reasonable fallback if the team would rather not own/maintain the check-set data: it's actively
enough maintained, Apache-2.0, technically sound (16 KB-safe as of `0.1.2`), and has years of production
mileage. The trade-off is the recurring false-positive reports tied to the exact signals this handler needs,
its opaque any-signal-trips-it default, and an extra native binary in a security-sensitive module — all
avoidable by hand-rolling against the same public data.

### Kotlin sketch

```kotlin
enum class Threat(val wireName: String) {
    ROOTED("rooted"),
    // SCREEN_RECORDING("screenRecording") — handled elsewhere
}

class SecurityEnvironmentHandler(
    private val context: Context,
    private val handlerScope: CoroutineScope, // tied to plugin/engine lifecycle
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "assessPosture" -> assessPosture(result)
            else -> result.notImplemented()
        }
    }

    private fun assessPosture(result: MethodChannel.Result) {
        handlerScope.launch {
            val threats = withContext(Dispatchers.IO) { collectThreats() }
            withContext(Dispatchers.Main) {
                result.success(
                    mapOf(
                        "posture" to if (threats.isEmpty()) "secure" else "compromised",
                        "threats" to threats.map { it.wireName },
                    )
                )
            }
        }
    }

    // Runs on Dispatchers.IO. Every check is independent; threshold below absorbs
    // single-signal false positives (custom ROMs, OEM debug props, systemless root).
    private fun collectThreats(): Set<Threat> {
        var signals = 0
        if (hasSuBinary()) signals++
        if (hasSuViaWhich()) signals++
        if (hasTestKeys()) signals++          // cheap: static field, but keep it in the IO batch for simplicity
        if (hasDangerousProps()) signals++
        if (hasRootPackage()) signals++
        if (hasWritableSystemPartition()) signals++

        return if (signals >= ROOT_SIGNAL_THRESHOLD) setOf(Threat.ROOTED) else emptySet()
    }

    private fun hasSuBinary(): Boolean =
        SU_DIRS.any { File(it, "su").exists() }

    private fun hasSuViaWhich(): Boolean = runCatching {
        val proc = ProcessBuilder("which", "su").redirectErrorStream(true).start()
        val out = proc.inputStream.bufferedReader().readText()
        val exited = proc.waitFor(SHELL_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        if (!exited) proc.destroyForcibly()
        exited && out.trim().isNotEmpty()
    }.getOrDefault(false)

    private fun hasTestKeys(): Boolean =
        Build.TAGS?.contains("test-keys") == true

    private fun hasDangerousProps(): Boolean = runCatching {
        val proc = ProcessBuilder("getprop").redirectErrorStream(true).start()
        val out = proc.inputStream.bufferedReader().readText()
        proc.waitFor(SHELL_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        out.contains("[ro.debuggable]: [1]") || out.contains("[ro.secure]: [0]")
    }.getOrDefault(false)

    private fun hasRootPackage(): Boolean = ROOT_PACKAGES.any { pkg ->
        runCatching {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(pkg, 0)
            true
        }.getOrDefault(false)
    }

    private fun hasWritableSystemPartition(): Boolean = runCatching {
        File("/proc/mounts").readLines().any { line ->
            RW_CHECK_PATHS.any { path -> line.contains(" $path ") } &&
                line.split(" ").getOrNull(3)?.split(",")?.contains("rw") == true
        }
    }.getOrDefault(false)

    private companion object {
        const val ROOT_SIGNAL_THRESHOLD = 2
        const val SHELL_TIMEOUT_MS = 1_000L
        val SU_DIRS = listOf(
            "/system/bin", "/system/xbin", "/sbin", "/system_ext/bin",
            "/system/bin/failsafe", "/data/local/xbin", "/data/local/bin", "/data/local", "/su/bin",
        )
        val ROOT_PACKAGES = listOf(
            "com.topjohnwu.magisk", "eu.chainfire.supersu", "com.noshufou.android.su",
            "com.koushikdutta.superuser", "me.weishu.kernelsu",
        )
        val RW_CHECK_PATHS = listOf("/system", "/vendor")
    }
}
```

```xml
<!-- AndroidManifest.xml — required on targetSdk 36 for hasRootPackage() to see anything -->
<queries>
    <package android:name="com.topjohnwu.magisk" />
    <package android:name="eu.chainfire.supersu" />
    <package android:name="com.noshufou.android.su" />
    <package android:name="com.koushikdutta.superuser" />
    <package android:name="me.weishu.kernelsu" />
</queries>
```

## Open questions / caveats

- **Channel contract (blocking this ticket)**: the sketch above returns a single `Threat.ROOTED` for any
  combination of fired signals. Decide whether `assessPosture` should also carry a diagnostic detail — e.g. a
  `signals: ["su_binary","dangerous_props"]` array — for support/triage and for tuning the threshold later, or
  whether that stays as Kotlin-side-only logging and the wire payload remains just `{posture, threats}`. This
  research did not resolve that; it's a product/API-surface decision, not a technical constraint.
- The `ro.secure`/`ro.debuggable` → `eng`/`userdebug`/`user` build-variant mapping is extremely well-established
  Android platform knowledge, but this research could not pin a single AOSP page stating the exact value table
  in one place; the mechanism (RootBeer's `checkForDangerousProps` reading exactly these two properties) is
  independently confirmed from the library source itself, which is what the recommendation relies on.
- Magisk's Zygisk DenyList/Shamiko hiding capability is corroborated by multiple community sources but not by a
  Magisk first-party doc page fetched in this session — treat as UNVERIFIED-against-primary-source, though
  widely reported.
- `KernelSU`'s manager `applicationId` is driven by a Gradle property in its build config, not a hardcoded
  literal — the shipped default could not be confirmed within this research's time-box; `me.weishu.kernelsu`
  (the `namespace`) is a reasonable default to check but may not match every build.
- All heuristics here (hand-rolled or RootBeer) are best-effort signals, not a security boundary — both the
  library's own README and standard industry guidance point to Play Integrity API for a real attestation, which
  is explicitly out of scope for this ticket.

## Sources

- [RootBeer — GitHub repo](https://github.com/scottyab/rootbeer)
- [RootBeer — README.md](https://raw.githubusercontent.com/scottyab/rootbeer/master/README.md)
- [RootBeer — RootBeer.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/RootBeer.java)
- [RootBeer — Const.java](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/java/com/scottyab/rootbeer/Const.java)
- [RootBeer — rootbeerlib/build.gradle.kts](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/build.gradle.kts)
- [RootBeer — CMakeLists.txt](https://raw.githubusercontent.com/scottyab/rootbeer/master/rootbeerlib/src/main/cpp/CMakeLists.txt)
- [RootBeer — Releases](https://github.com/scottyab/rootbeer/releases)
- [RootBeer — repo metadata (GitHub API)](https://api.github.com/repos/scottyab/rootbeer)
- [RootBeer — Issue #226](https://github.com/scottyab/rootbeer/issues/226)
- [RootBeer — Issue #181](https://github.com/scottyab/rootbeer/issues/181)
- [Maven Central — rootbeer-lib maven-metadata.xml](https://repo1.maven.org/maven2/com/scottyab/rootbeer-lib/maven-metadata.xml)
- [AOSP — Sign builds for release (test-keys vs release-keys)](https://source.android.com/docs/core/ota/sign_builds)
- [AOSP — Build Android (build variants)](https://source.android.com/docs/setup/build/building)
- [AOSP — Build.java source](https://android.googlesource.com/platform/frameworks/base/+/master/core/java/android/os/Build.java)
- [Android Developers — Package visibility filtering](https://developer.android.com/training/package-visibility)
- [Android Developers — Automatic package visibility](https://developer.android.com/training/package-visibility/automatic)
- [Android Developers — Declare package visibility needs](https://developer.android.com/training/package-visibility/declaring)
- [Android Developers — Support 16 KB page sizes](https://developer.android.com/guide/practices/page-sizes)
- [Android Developers Blog — Prepare your apps for 16 KB page size](https://android-developers.googleblog.com/2025/05/prepare-play-apps-for-devices-with-16kb-page-size.html)
- [Android Developers — Create and manage virtual devices](https://developer.android.com/studio/run/managing-avds)
- [kotlinx.coroutines — Dispatchers.IO](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/-dispatchers/-i-o.html)
- [Android Developers — Improve app performance with Kotlin coroutines](https://developer.android.com/kotlin/coroutines/coroutines-adv)
- [Android Developers — Keep your app responsive (ANRs)](https://developer.android.com/topic/performance/anrs/keep-your-app-responsive)
- [KernelSU — What is KernelSU](https://kernelsu.org/guide/what-is-kernelsu.html)
- [KernelSU — Difference with Magisk](https://kernelsu.org/guide/difference-with-magisk.html)
- [KernelSU — manager/app/build.gradle.kts](https://raw.githubusercontent.com/tiann/KernelSU/main/manager/app/build.gradle.kts)
