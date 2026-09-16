# security_guard Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `security_guard` feature end to end against fakes — domain model, ports, the one use case, and the presentation layer that owns Secure Window and posture lifecycle — with no native (Kotlin) adapter yet.

**Architecture:** Second of five implementation plans (Plan 1: workspace/core/brand_engine, done — `develop` at commit `5037477`). `security_guard` depends only on `core` and `brand_engine`, both already built, so this plan is fully self-contained: every type, port, and widget is tested against a hand-written fake, never a real channel. `docs/architecture.md` §5, §7.2, §8, §11 are the source of truth for every shape below; `CONTEXT.md` for every domain term.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12 via FVM. New dependencies this plan adds: `equatable` (value equality for the domain types — the charted convention, `docs/architecture.md` §2 principle 3 / decision from initial charting), `flutter_bloc` (the `SecurityPostureCubit`), `get_it` (the feature's `di.dart`), `bloc_test` (dev, for the cubit test).

**Carry-forward from Plan 1** (apply automatically, don't re-derive): the lint command is `dart analyze --fatal-infos`, never `flutter analyze`; every `import_lint` rule needs an explicit `except: []`; see `docs/architecture.md` §3.3.

**Reference:** `docs/architecture.md` §4 (module interfaces — `features/security_guard`'s exact export list), §5 (domain model), §5.1 (ports), §7.2 (`SecurityPostureCubit`), §8 (assessment flow), §11 (Secure Window). `docs/adr/0005-use-cases-only-where-logic-lives.md` for why there is exactly one use case here.

**Scope boundary — what this plan does NOT build:** `ChannelSecurityEnvironment`, `ChannelSecureWindow` (the real Kotlin-backed adapters — native bridge plan), `SecurityScanView`/`PostureBanner` (the visual widgets — a short follow-up plan, since they're substantial ported prototype code with their own isolation test and don't block anything else), `lib/features/payment/`, the composition root. This plan's success criterion: `flutter test` passes with `security_guard` fully covered against fakes, and `security_guard_via_barrel`/`no_reverse_dependency` are wired (though not yet smoke-testable — `features/payment` doesn't exist).

---

## File structure

```
lib/features/security_guard/
├── security_guard.dart                    # new — barrel, grown incrementally across Tasks 2–11
├── di.dart                                 # new — registerSecurityModule
└── src/
    ├── domain/
    │   ├── threat_assessment.dart          # new — AssessmentResult (Detected|Clear|Unavailable), ThreatAssessment
    │   ├── security_posture.dart           # new — SecurityClassification, SecurityPosture
    │   ├── policy_verdict.dart             # new — PolicyVerdict, evaluatePosturePolicy(), PostureUpdate
    │   ├── security_environment.dart       # new — port
    │   ├── secure_window.dart              # new — port
    │   ├── security_brand_config.dart      # new
    │   └── watch_posture_verdict.dart      # new — the one use case
    └── presentation/
        ├── posture_state.dart              # new
        ├── security_posture_cubit.dart     # new
        ├── secure_window_controller.dart   # new
        └── secure_session_scope.dart       # new

test/
├── support/fakes/
│   ├── fake_security_environment.dart      # new
│   └── fake_secure_window.dart             # new
└── features/security_guard/
    ├── threat_assessment_test.dart         # new
    ├── security_posture_test.dart          # new
    ├── policy_verdict_test.dart            # new
    ├── watch_posture_verdict_test.dart      # new
    ├── security_posture_cubit_test.dart    # new
    ├── secure_window_controller_test.dart  # new
    ├── secure_session_scope_test.dart      # new
    └── di_test.dart                        # new

docs/verification/
└── 2026-09-17-security-guard-lint-verification.md   # new — Task 12's audit note
```

`PostureUpdate` is folded into `policy_verdict.dart` (Task 4) — it's a two-field tuple over `SecurityPosture`/`PolicyVerdict`, changes only alongside `evaluatePosturePolicy`, and giving it its own file would be a one-class file for no reason (`codebase-design`: files that change together live together).

---

### Task 1: Add dependencies; extend the lint config for the feature-first rules

**Files:**
- Modify: `pubspec.yaml`, `analysis_options.yaml`

- [ ] **Step 1: Add the new dependencies**

```bash
~/fvm/versions/3.44.6/bin/flutter pub add equatable flutter_bloc get_it
~/fvm/versions/3.44.6/bin/flutter pub add --dev bloc_test
```

(Letting `pub add` resolve current compatible versions avoids guessing exact version numbers here — it writes `pubspec.yaml` and `pubspec.lock` itself.)

- [ ] **Step 2: Extend `analysis_options.yaml` with the feature-first layer rules**

Add these four rules (with `except: []`, per the Plan 1 finding) alongside the three existing module-wall rules, under `import_lint: rules:`:

```yaml
    domain_no_data:
      target: "package:payment_module/features/*/src/domain/**.dart"
      from: "package:payment_module/features/*/src/data/**.dart"
      except: []
    domain_no_presentation:
      target: "package:payment_module/features/*/src/domain/**.dart"
      from: "package:payment_module/features/*/src/presentation/**.dart"
      except: []
    domain_no_flutter:
      target: "package:payment_module/features/*/src/domain/**.dart"
      from: "package:flutter/**.dart"
      except: []
    presentation_no_data:
      target: "package:payment_module/features/*/src/presentation/**.dart"
      from: "package:payment_module/features/*/src/data/**.dart"
      except: []
```

Also add the two feature-pair rules now — their globs reference `features/payment`, which doesn't exist yet, so they're inert until Plan 3, but adding them now means Plan 3 only has to write `features/payment`, not touch this file again:

```yaml
    security_guard_via_barrel:
      target: "package:payment_module/features/payment/**.dart"
      from: "package:payment_module/features/security_guard/src/**.dart"
      except: []
    no_reverse_dependency:
      target: "package:payment_module/features/security_guard/**.dart"
      from: "package:payment_module/features/payment/**.dart"
      except: []
```

- [ ] **Step 3: Verify the workspace still analyzes clean**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!` (the new rules match nothing yet — `lib/features/` doesn't exist).

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock analysis_options.yaml
git commit -m "chore: add equatable, flutter_bloc, get_it, bloc_test; extend lint rules for features/*"
```

---

### Task 2: `ThreatAssessment` and `AssessmentResult`

**Files:**
- Create: `lib/features/security_guard/security_guard.dart` (barrel — created here, grown through Task 11)
- Create: `lib/features/security_guard/src/domain/threat_assessment.dart`
- Test: `test/features/security_guard/threat_assessment_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  group('AssessmentResult', () {
    test('two Detected results are equal', () {
      expect(const Detected(), equals(const Detected()));
    });

    test('two Clear results are equal', () {
      expect(const Clear(), equals(const Clear()));
    });

    test('two Unavailable results with the same reason are equal', () {
      expect(
        const Unavailable(UnavailableReason.apiLevel),
        equals(const Unavailable(UnavailableReason.apiLevel)),
      );
    });

    test('Unavailable results with different reasons are not equal', () {
      expect(
        const Unavailable(UnavailableReason.apiLevel),
        isNot(equals(const Unavailable(UnavailableReason.error))),
      );
    });
  });

  group('ThreatAssessment', () {
    test('two assessments with the same kind and result are equal', () {
      const a = ThreatAssessment(kind: ThreatKind.rooted, result: Clear());
      const b = ThreatAssessment(kind: ThreatKind.rooted, result: Clear());
      expect(a, equals(b));
    });

    test('assessments with different kinds are not equal even with the same result', () {
      const a = ThreatAssessment(kind: ThreatKind.rooted, result: Clear());
      const b = ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear());
      expect(a, isNot(equals(b)));
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/threat_assessment_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/features/security_guard/security_guard.dart'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/domain/threat_assessment.dart
import 'package:equatable/equatable.dart';

import '../../../../core/threat.dart';

/// Why a Threat's check could not run. See CONTEXT.md → Threat Assessment.
enum UnavailableReason { apiLevel, error }

/// The result of checking for one kind of Threat: detected, clear, or unavailable when the check
/// cannot run on this device. See CONTEXT.md → Threat Assessment.
sealed class AssessmentResult extends Equatable {
  const AssessmentResult();
}

final class Detected extends AssessmentResult {
  const Detected();
  @override
  List<Object?> get props => const [];
}

final class Clear extends AssessmentResult {
  const Clear();
  @override
  List<Object?> get props => const [];
}

final class Unavailable extends AssessmentResult {
  const Unavailable(this.reason);
  final UnavailableReason reason;
  @override
  List<Object?> get props => [reason];
}

/// The result of checking for one kind of Threat. See CONTEXT.md → Threat Assessment.
class ThreatAssessment extends Equatable {
  const ThreatAssessment({required this.kind, required this.result});

  final ThreatKind kind;
  final AssessmentResult result;

  @override
  List<Object?> get props => [kind, result];
}
```

```dart
// lib/features/security_guard/security_guard.dart
export 'src/domain/threat_assessment.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/threat_assessment_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/threat_assessment_test.dart
git commit -m "feat(security_guard): add AssessmentResult and ThreatAssessment"
```

---

### Task 3: `SecurityPosture`

**Files:**
- Create: `lib/features/security_guard/src/domain/security_posture.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)
- Test: `test/features/security_guard/security_posture_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

void main() {
  group('SecurityPosture.classification', () {
    test('is secure when every assessment is clear', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      expect(posture.classification, SecurityClassification.secure);
    });

    test('is compromised when any assessment is detected, even if another is unavailable', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Unavailable(UnavailableReason.apiLevel)),
      ]);
      expect(posture.classification, SecurityClassification.compromised);
    });

    test('is unverified when none are detected but at least one is unavailable', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Unavailable(UnavailableReason.apiLevel)),
      ]);
      expect(posture.classification, SecurityClassification.unverified);
    });
  });

  test('resultFor returns the assessment result for the requested kind', () {
    final posture = SecurityPosture(const [
      ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
      ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
    ]);
    expect(posture.resultFor(ThreatKind.rooted), const Detected());
    expect(posture.resultFor(ThreatKind.screenRecording), const Clear());
  });

  test('asserts when a ThreatKind is missing', () {
    expect(
      () => SecurityPosture(const [ThreatAssessment(kind: ThreatKind.rooted, result: Clear())]),
      throwsA(isA<AssertionError>()),
    );
  });

  test('asserts on a duplicate ThreatKind', () {
    expect(
      () => SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]),
      throwsA(isA<AssertionError>()),
    );
  });

  test('two postures with the same assessments are equal', () {
    SecurityPosture build() => SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]);
    expect(build(), equals(build()));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/security_posture_test.dart`
Expected: FAIL to compile — `Undefined class 'SecurityPosture'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/domain/security_posture.dart
import 'package:equatable/equatable.dart';

import '../../../../core/threat.dart';
import 'threat_assessment.dart';

/// How a Security Posture is classified once every Threat has been assessed. See CONTEXT.md →
/// Security Posture.
enum SecurityClassification { secure, compromised, unverified }

/// The outcome of assessing the device environment: one Threat Assessment per kind of Threat.
/// See CONTEXT.md → Security Posture.
class SecurityPosture extends Equatable {
  SecurityPosture(Iterable<ThreatAssessment> assessments) : assessments = List.unmodifiable(assessments) {
    final kinds = assessments.map((a) => a.kind).toSet();
    assert(kinds.length == assessments.length, 'Duplicate ThreatKind in SecurityPosture');
    assert(
      kinds.containsAll(ThreatKind.values),
      'SecurityPosture is missing an assessment for '
      '${ThreatKind.values.where((k) => !kinds.contains(k))}',
    );
  }

  final List<ThreatAssessment> assessments;

  AssessmentResult resultFor(ThreatKind kind) => assessments.firstWhere((a) => a.kind == kind).result;

  /// Secure — every check clear. Compromised — any Threat detected. Unverified — none detected,
  /// but at least one check could not run.
  SecurityClassification get classification {
    if (assessments.any((a) => a.result is Detected)) return SecurityClassification.compromised;
    if (assessments.any((a) => a.result is Unavailable)) return SecurityClassification.unverified;
    return SecurityClassification.secure;
  }

  @override
  List<Object?> get props => [assessments];
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/domain/security_posture.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/security_posture_test.dart`
Expected: `00:00 +7: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/security_posture_test.dart
git commit -m "feat(security_guard): add SecurityPosture and SecurityClassification"
```

---

### Task 4: `PolicyVerdict`, `evaluatePosturePolicy`, `PostureUpdate`

**Files:**
- Create: `lib/features/security_guard/src/domain/policy_verdict.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)
- Test: `test/features/security_guard/policy_verdict_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

PosturePolicy _retailPolicy() => PosturePolicy(
      onDetected: {
        ThreatKind.rooted: DetectedResponse.block,
        ThreatKind.screenRecording: DetectedResponse.warn,
      },
      onUnavailable: {
        ThreatKind.rooted: UnavailableResponse.allow,
        ThreatKind.screenRecording: UnavailableResponse.allow,
      },
    );

PosturePolicy _utilityPolicy() => PosturePolicy(
      onDetected: {
        ThreatKind.rooted: DetectedResponse.block,
        ThreatKind.screenRecording: DetectedResponse.block,
      },
      onUnavailable: {
        ThreatKind.rooted: UnavailableResponse.notice,
        ThreatKind.screenRecording: UnavailableResponse.notice,
      },
    );

void main() {
  group('evaluatePosturePolicy', () {
    test('a fully clear posture produces an empty verdict', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
      ]);
      final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
      expect(verdict.blockers, isEmpty);
      expect(verdict.warnings, isEmpty);
      expect(verdict.notices, isEmpty);
      expect(verdict.isBlocked, isFalse);
    });

    test("Retail policy: a detected root blocks, a detected recorder only warns", () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Detected()),
      ]);
      final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
      expect(verdict.blockers, {ThreatKind.rooted});
      expect(verdict.warnings, {ThreatKind.screenRecording});
      expect(verdict.isBlocked, isTrue);
    });

    test('Retail policy: an unavailable check is allowed silently — no notice, no block', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Unavailable(UnavailableReason.apiLevel)),
      ]);
      final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
      expect(verdict.blockers, isEmpty);
      expect(verdict.notices, isEmpty);
      expect(verdict.isBlocked, isFalse);
    });

    test('Utility policy: an unavailable check produces a notice', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Unavailable(UnavailableReason.apiLevel)),
      ]);
      final verdict = evaluatePosturePolicy(_utilityPolicy(), posture);
      expect(verdict.notices, {ThreatKind.screenRecording});
      expect(verdict.isBlocked, isFalse);
    });

    test('Utility policy: both Threat kinds block when detected', () {
      final posture = SecurityPosture(const [
        ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
        ThreatAssessment(kind: ThreatKind.screenRecording, result: Detected()),
      ]);
      final verdict = evaluatePosturePolicy(_utilityPolicy(), posture);
      expect(verdict.blockers, {ThreatKind.rooted, ThreatKind.screenRecording});
      expect(verdict.isBlocked, isTrue);
    });
  });

  test('PostureUpdate bundles a posture and its verdict, with value equality', () {
    final posture = SecurityPosture(const [
      ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
      ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
    ]);
    final verdict = evaluatePosturePolicy(_retailPolicy(), posture);
    final a = PostureUpdate(posture: posture, verdict: verdict);
    final b = PostureUpdate(posture: posture, verdict: verdict);
    expect(a, equals(b));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/policy_verdict_test.dart`
Expected: FAIL to compile — `The function 'evaluatePosturePolicy' isn't defined`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/domain/policy_verdict.dart
import 'package:equatable/equatable.dart';

import '../../../../core/threat.dart';
import 'security_posture.dart';
import 'threat_assessment.dart';

/// The result of applying a Posture Policy to a Security Posture: which Threats block the
/// payment, which only warn, and which checks deserve a notice. See CONTEXT.md → Policy Verdict.
class PolicyVerdict extends Equatable {
  const PolicyVerdict({required this.blockers, required this.warnings, required this.notices});

  final Set<ThreatKind> blockers;
  final Set<ThreatKind> warnings;
  final Set<ThreatKind> notices;

  bool get isBlocked => blockers.isNotEmpty;

  @override
  List<Object?> get props => [blockers, warnings, notices];
}

/// Applies [policy] to [posture]. Pure — the internal seam of `WatchPostureVerdict`, exported so
/// it can be unit-tested directly. See docs/architecture.md §5.1 and
/// docs/adr/0005-use-cases-only-where-logic-lives.md.
PolicyVerdict evaluatePosturePolicy(PosturePolicy policy, SecurityPosture posture) {
  final blockers = <ThreatKind>{};
  final warnings = <ThreatKind>{};
  final notices = <ThreatKind>{};

  for (final assessment in posture.assessments) {
    switch (assessment.result) {
      case Detected():
        switch (policy.onDetected[assessment.kind]!) {
          case DetectedResponse.block:
            blockers.add(assessment.kind);
          case DetectedResponse.warn:
            warnings.add(assessment.kind);
        }
      case Clear():
        break;
      case Unavailable():
        switch (policy.onUnavailable[assessment.kind]!) {
          case UnavailableResponse.notice:
            notices.add(assessment.kind);
          case UnavailableResponse.allow:
            break;
        }
    }
  }

  return PolicyVerdict(blockers: blockers, warnings: warnings, notices: notices);
}

/// A Security Posture paired with the Policy Verdict derived from it — what `WatchPostureVerdict`
/// streams.
class PostureUpdate extends Equatable {
  const PostureUpdate({required this.posture, required this.verdict});

  final SecurityPosture posture;
  final PolicyVerdict verdict;

  @override
  List<Object?> get props => [posture, verdict];
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/domain/policy_verdict.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/policy_verdict_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/policy_verdict_test.dart
git commit -m "feat(security_guard): add evaluatePosturePolicy, PolicyVerdict, PostureUpdate"
```

---

### Task 5: `SecurityEnvironment` port and its fake

**Files:**
- Create: `lib/features/security_guard/src/domain/security_environment.dart`
- Create: `test/support/fakes/fake_security_environment.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)

This task has no `security_guard`-specific test of its own — the port is an `abstract class` (nothing to unit test), and the fake is exercised by Task 8's use-case test. Both are needed together because the fake is written directly against the port's shape.

- [ ] **Step 1: Implement the port**

```dart
// lib/features/security_guard/src/domain/security_environment.dart
import 'security_posture.dart';

/// Assesses the device's Security Posture. One source of truth: [assess] re-runs the one-shot
/// checks and pushes a snapshot onto [posture]; a live signal (the API 35+ screen-recorder
/// callback) pushes its own transitions independently. See docs/architecture.md §5.1, §8.
abstract class SecurityEnvironment {
  Future<void> assess();
  Stream<SecurityPosture> get posture;
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/domain/security_environment.dart';
```

- [ ] **Step 2: Implement the fake**

```dart
// test/support/fakes/fake_security_environment.dart
import 'dart:async';

import 'package:payment_module/features/security_guard/security_guard.dart';

/// A scripted [SecurityEnvironment] for tests. Push postures via [pushPosture]; [assess] only
/// records that it was called — push a posture separately to simulate its result arriving.
class FakeSecurityEnvironment implements SecurityEnvironment {
  final _controller = StreamController<SecurityPosture>.broadcast();
  int assessCallCount = 0;

  @override
  Future<void> assess() async {
    assessCallCount++;
  }

  @override
  Stream<SecurityPosture> get posture => _controller.stream;

  void pushPosture(SecurityPosture posture) => _controller.add(posture);

  Future<void> dispose() => _controller.close();
}
```

- [ ] **Step 3: Verify the workspace still compiles and analyzes clean**

Run: `~/fvm/versions/3.44.6/bin/flutter analyze` then `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: both `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/security_guard test/support/fakes/fake_security_environment.dart
git commit -m "feat(security_guard): add SecurityEnvironment port and its fake"
```

---

### Task 6: `SecureWindow` port and its fake

**Files:**
- Create: `lib/features/security_guard/src/domain/secure_window.dart`
- Create: `test/support/fakes/fake_secure_window.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)

Same shape as Task 5 — no test of its own; exercised by Task 11's controller test.

- [ ] **Step 1: Implement the port**

```dart
// lib/features/security_guard/src/domain/secure_window.dart
/// Holds or releases the Secure Window (`FLAG_SECURE`) — blocks screenshots and screen sharing
/// while the payment screen is visible. See CONTEXT.md → Secure Window.
abstract class SecureWindow {
  Future<void> setSecure(bool secure);
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/domain/secure_window.dart';
```

- [ ] **Step 2: Implement the fake**

```dart
// test/support/fakes/fake_secure_window.dart
import 'package:payment_module/features/security_guard/security_guard.dart';

/// A recording [SecureWindow] for tests: every successful call is appended to [calls]. Set
/// [errorToThrow] to make the next call throw once (then reset itself).
class FakeSecureWindow implements SecureWindow {
  final calls = <bool>[];
  Object? errorToThrow;

  @override
  Future<void> setSecure(bool secure) async {
    if (errorToThrow != null) {
      final error = errorToThrow!;
      errorToThrow = null;
      throw error;
    }
    calls.add(secure);
  }
}
```

- [ ] **Step 3: Verify**

Run: `~/fvm/versions/3.44.6/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/features/security_guard test/support/fakes/fake_secure_window.dart
git commit -m "feat(security_guard): add SecureWindow port and its fake"
```

---

### Task 7: `SecurityBrandConfig`

**Files:**
- Create: `lib/features/security_guard/src/domain/security_brand_config.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)

A one-field wrapper (`BrandFeatureConfig` subclass) — no behaviour to unit test on its own; `BrandConfig.feature<T>()` already covers the lookup mechanics (Plan 1, Task 7's test). Verified here by a one-line analyze check instead of a dedicated test file, matching Task 5/6's shape.

- [ ] **Step 1: Implement**

```dart
// lib/features/security_guard/src/domain/security_brand_config.dart
import '../../../../brand_engine/brand_engine.dart';
import '../../../../core/threat.dart';

/// A Brand's slice of security configuration: its Posture Policy. See docs/architecture.md §6.
class SecurityBrandConfig extends BrandFeatureConfig {
  const SecurityBrandConfig({required this.policy});
  final PosturePolicy policy;
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/domain/security_brand_config.dart';
```

- [ ] **Step 2: Verify**

Run: `~/fvm/versions/3.44.6/bin/flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/security_guard
git commit -m "feat(security_guard): add SecurityBrandConfig"
```

---

### Task 8: `WatchPostureVerdict` — the one use case

**Files:**
- Create: `lib/features/security_guard/src/domain/watch_posture_verdict.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)
- Test: `test/features/security_guard/watch_posture_verdict_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_security_environment.dart';

void main() {
  late FakeSecurityEnvironment environment;
  late PosturePolicy policy;

  setUp(() {
    environment = FakeSecurityEnvironment();
    policy = PosturePolicy(
      onDetected: {
        ThreatKind.rooted: DetectedResponse.block,
        ThreatKind.screenRecording: DetectedResponse.warn,
      },
      onUnavailable: {
        ThreatKind.rooted: UnavailableResponse.allow,
        ThreatKind.screenRecording: UnavailableResponse.allow,
      },
    );
  });

  tearDown(() => environment.dispose());

  test('calling triggers assess() on the environment', () {
    final subscription = WatchPostureVerdict(environment, policy)().listen((_) {});
    expect(environment.assessCallCount, 1);
    subscription.cancel();
  });

  test('emits a PostureUpdate with the policy applied, for every posture pushed', () async {
    final updates = <PostureUpdate>[];
    final subscription = WatchPostureVerdict(environment, policy)().listen(updates.add);

    final compromised = SecurityPosture(const [
      ThreatAssessment(kind: ThreatKind.rooted, result: Detected()),
      ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
    ]);
    environment.pushPosture(compromised);
    await Future<void>.delayed(Duration.zero);

    expect(updates, hasLength(1));
    expect(updates.single.posture, compromised);
    expect(updates.single.verdict.blockers, {ThreatKind.rooted});

    await subscription.cancel();
  });

  test('does not re-emit for a posture identical to the last one (distinct)', () async {
    final updates = <PostureUpdate>[];
    final subscription = WatchPostureVerdict(environment, policy)().listen(updates.add);

    SecurityPosture clear() => SecurityPosture(const [
          ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
          ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
        ]);
    environment.pushPosture(clear());
    environment.pushPosture(clear());
    await Future<void>.delayed(Duration.zero);

    expect(updates, hasLength(1));

    await subscription.cancel();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/watch_posture_verdict_test.dart`
Expected: FAIL to compile — `Undefined class 'WatchPostureVerdict'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/domain/watch_posture_verdict.dart
import 'dart:async';

import '../../../../core/threat.dart';
import 'policy_verdict.dart';
import 'security_environment.dart';

/// Subscribes to the Security Environment, applies a Brand's Posture Policy to every Security
/// Posture it reports, and triggers the first assessment. The one use case in `security_guard` —
/// see docs/adr/0005-use-cases-only-where-logic-lives.md.
class WatchPostureVerdict {
  WatchPostureVerdict(this._environment, this._policy);

  final SecurityEnvironment _environment;
  final PosturePolicy _policy;

  Stream<PostureUpdate> call() async* {
    unawaited(_environment.assess());
    yield* _environment.posture
        .map((posture) => PostureUpdate(posture: posture, verdict: evaluatePosturePolicy(_policy, posture)))
        .distinct();
  }
}
```

`PostureUpdate` lives in `policy_verdict.dart` (Task 4) — the `show` import above just documents which symbol is used; remove it if the analyzer flags it as redundant with the file's other import from the same path (it doesn't import anything else from `policy_verdict.dart` here, so keep the explicit `show`, or simplify to `import 'policy_verdict.dart';` — either compiles, use whichever `dart format` leaves alone).

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/domain/watch_posture_verdict.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/watch_posture_verdict_test.dart`
Expected: `00:00 +3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/watch_posture_verdict_test.dart
git commit -m "feat(security_guard): add WatchPostureVerdict use case"
```

---

### Task 9: `PostureState` and `SecurityPostureCubit`

**Files:**
- Create: `lib/features/security_guard/src/presentation/posture_state.dart`
- Create: `lib/features/security_guard/src/presentation/security_posture_cubit.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add two export lines)
- Test: `test/features/security_guard/security_posture_cubit_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_security_environment.dart';

void main() {
  late FakeSecurityEnvironment environment;
  late PosturePolicy policy;

  setUp(() {
    environment = FakeSecurityEnvironment();
    policy = PosturePolicy(
      onDetected: {
        ThreatKind.rooted: DetectedResponse.block,
        ThreatKind.screenRecording: DetectedResponse.warn,
      },
      onUnavailable: {
        ThreatKind.rooted: UnavailableResponse.allow,
        ThreatKind.screenRecording: UnavailableResponse.allow,
      },
    );
  });

  tearDown(() => environment.dispose());

  test('the initial state has no posture and hasFirstAssessment is false', () {
    final cubit = SecurityPostureCubit(environment, policy);
    expect(cubit.state.posture, isNull);
    expect(cubit.state.hasFirstAssessment, isFalse);
    cubit.close();
  });

  test('subscribing triggers assess() on the environment', () {
    final cubit = SecurityPostureCubit(environment, policy);
    expect(environment.assessCallCount, 1);
    cubit.close();
  });

  blocTest<SecurityPostureCubit, PostureState>(
    'emits a state with hasFirstAssessment true after the first posture arrives',
    build: () => SecurityPostureCubit(environment, policy),
    act: (cubit) => environment.pushPosture(SecurityPosture(const [
      ThreatAssessment(kind: ThreatKind.rooted, result: Clear()),
      ThreatAssessment(kind: ThreatKind.screenRecording, result: Clear()),
    ])),
    expect: () => [
      isA<PostureState>().having((s) => s.hasFirstAssessment, 'hasFirstAssessment', isTrue),
    ],
  );

  test('onResumed() calls assess() again', () {
    final cubit = SecurityPostureCubit(environment, policy);
    expect(environment.assessCallCount, 1);
    cubit.onResumed();
    expect(environment.assessCallCount, 2);
    cubit.close();
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/security_posture_cubit_test.dart`
Expected: FAIL to compile — `Undefined class 'SecurityPostureCubit'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/presentation/posture_state.dart
import 'package:equatable/equatable.dart';

import '../domain/policy_verdict.dart';
import '../domain/security_posture.dart';

/// State of [SecurityPostureCubit]. See docs/architecture.md §7.2.
class PostureState extends Equatable {
  const PostureState({this.posture, this.verdict});

  const PostureState.initial() : this();

  final SecurityPosture? posture;
  final PolicyVerdict? verdict;

  bool get hasFirstAssessment => posture != null;

  PostureState copyWith({SecurityPosture? posture, PolicyVerdict? verdict}) =>
      PostureState(posture: posture ?? this.posture, verdict: verdict ?? this.verdict);

  @override
  List<Object?> get props => [posture, verdict];
}
```

```dart
// lib/features/security_guard/src/presentation/security_posture_cubit.dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/threat.dart';
import '../domain/policy_verdict.dart' show PostureUpdate;
import '../domain/security_environment.dart';
import '../domain/watch_posture_verdict.dart';
import 'posture_state.dart';

/// Subscribes to [WatchPostureVerdict] for as long as the payment screen is mounted; re-runs the
/// one-shot checks on resume. Thin by design — its value is the seam and its reuse by any future
/// secure screen, not logic. See docs/architecture.md §7.2.
class SecurityPostureCubit extends Cubit<PostureState> {
  SecurityPostureCubit(SecurityEnvironment environment, PosturePolicy policy)
      : _environment = environment,
        super(const PostureState.initial()) {
    _subscription = WatchPostureVerdict(environment, policy)().listen(_onUpdate);
  }

  final SecurityEnvironment _environment;
  late final StreamSubscription<PostureUpdate> _subscription;

  void _onUpdate(PostureUpdate update) {
    emit(state.copyWith(posture: update.posture, verdict: update.verdict));
  }

  /// Called by the page's `AppLifecycleListener` when the app resumes.
  void onResumed() {
    unawaited(_environment.assess());
  }

  @override
  Future<void> close() {
    unawaited(_subscription.cancel());
    return super.close();
  }
}
```

```dart
// lib/features/security_guard/security_guard.dart — add these two lines
export 'src/presentation/posture_state.dart';
export 'src/presentation/security_posture_cubit.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/security_posture_cubit_test.dart`
Expected: `00:00 +4: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/security_posture_cubit_test.dart
git commit -m "feat(security_guard): add PostureState and SecurityPostureCubit"
```

---

### Task 10: `SecureWindowController`

**Files:**
- Create: `lib/features/security_guard/src/presentation/secure_window_controller.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)
- Test: `test/features/security_guard/secure_window_controller_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_secure_window.dart';

void main() {
  late FakeSecureWindow window;
  late SecureWindowController controller;

  setUp(() {
    window = FakeSecureWindow();
    controller = SecureWindowController(window);
  });

  test('the first acquire() sets the flag; a second, nested acquire() does not call again', () async {
    await controller.acquire();
    await controller.acquire();
    expect(window.calls, [true]);
  });

  test('release() only clears the flag once the count returns to zero', () async {
    await controller.acquire();
    await controller.acquire();
    await controller.release();
    expect(window.calls, [true]); // still held — one acquire is still outstanding
    await controller.release();
    expect(window.calls, [true, false]);
  });

  test('release() without a matching acquire() asserts', () async {
    expect(() => controller.release(), throwsA(isA<AssertionError>()));
  });

  test('onResumed() re-asserts the flag while held', () async {
    await controller.acquire();
    await controller.onResumed();
    expect(window.calls, [true, true]);
  });

  test('onResumed() does nothing while not held', () async {
    await controller.onResumed();
    expect(window.calls, isEmpty);
  });

  test('a thrown error from setSecure during acquire() is swallowed, not rethrown', () async {
    window.errorToThrow = Exception('no activity attached');
    await controller.acquire(); // must not throw
    expect(window.calls, isEmpty); // the call that threw is not recorded as succeeded
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/secure_window_controller_test.dart`
Expected: FAIL to compile — `Undefined class 'SecureWindowController'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/presentation/secure_window_controller.dart
import '../domain/secure_window.dart';

/// Ref-counted holder of the Secure Window: calls [SecureWindow.setSecure] only on 0→1 (acquire)
/// and 1→0 (release) transitions, so stacked secure routes and dialogs never toggle the flag
/// twice. Errors from the native side are swallowed — the flow must not depend on this call
/// succeeding on the first try; the next [onResumed] retries. See docs/architecture.md §11.
class SecureWindowController {
  SecureWindowController(this._window);

  final SecureWindow _window;
  int _count = 0;

  Future<void> acquire() async {
    _count++;
    if (_count == 1) {
      await _setSecureSwallowingErrors(true);
    }
  }

  Future<void> release() async {
    assert(_count > 0, 'SecureWindowController.release() called more times than acquire()');
    _count--;
    if (_count == 0) {
      await _setSecureSwallowingErrors(false);
    }
  }

  Future<void> onResumed() async {
    if (_count > 0) {
      await _setSecureSwallowingErrors(true);
    }
  }

  Future<void> _setSecureSwallowingErrors(bool secure) async {
    try {
      await _window.setSecure(secure);
    } catch (_) {
      // Swallowed by design: a transient ServiceException (e.g. no Activity attached during a
      // config change) must not break the payment flow. The next onResumed() retries.
    }
  }
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/presentation/secure_window_controller.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/secure_window_controller_test.dart`
Expected: `00:00 +6: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/secure_window_controller_test.dart
git commit -m "feat(security_guard): add SecureWindowController"
```

---

### Task 11: `SecureSessionScope`

**Files:**
- Create: `lib/features/security_guard/src/presentation/secure_session_scope.dart`
- Modify: `lib/features/security_guard/security_guard.dart` (add one export line)
- Test: `test/features/security_guard/secure_session_scope_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_secure_window.dart';

void main() {
  testWidgets('mounting the scope acquires the Secure Window', (tester) async {
    final window = FakeSecureWindow();
    final controller = SecureWindowController(window);

    await tester.pumpWidget(
      SecureSessionScope(controller: controller, child: const SizedBox.shrink()),
    );

    expect(window.calls, [true]);
  });

  testWidgets('unmounting the scope releases the Secure Window', (tester) async {
    final window = FakeSecureWindow();
    final controller = SecureWindowController(window);

    await tester.pumpWidget(
      SecureSessionScope(controller: controller, child: const SizedBox.shrink()),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    expect(window.calls, [true, false]);
  });

  testWidgets('a second SecureSessionScope over the same controller acquires but does not toggle',
      (tester) async {
    final window = FakeSecureWindow();
    final controller = SecureWindowController(window);

    await tester.pumpWidget(
      SecureSessionScope(
        controller: controller,
        child: SecureSessionScope(controller: controller, child: const SizedBox.shrink()),
      ),
    );

    expect(window.calls, [true]); // one setSecure(true) call, not two
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/secure_session_scope_test.dart`
Expected: FAIL to compile — `Undefined class 'SecureSessionScope'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/src/presentation/secure_session_scope.dart
import 'package:flutter/widgets.dart';

import 'secure_window_controller.dart';

/// Holds the Secure Window for as long as this widget is mounted, and re-asserts it on resume.
/// Ref-counted via [SecureWindowController] so stacked secure routes and dialogs don't flicker
/// the flag. See docs/architecture.md §11 — "one lifetime, two owners" (this scope and
/// `SecurityPostureCubit` are the two; they are deliberately not merged).
class SecureSessionScope extends StatefulWidget {
  const SecureSessionScope({super.key, required this.controller, required this.child});

  final SecureWindowController controller;
  final Widget child;

  @override
  State<SecureSessionScope> createState() => _SecureSessionScopeState();
}

class _SecureSessionScopeState extends State<SecureSessionScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.acquire();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.controller.onResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

```dart
// lib/features/security_guard/security_guard.dart — add this line
export 'src/presentation/secure_session_scope.dart';
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/secure_session_scope_test.dart`
Expected: `00:00 +3: All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/secure_session_scope_test.dart
git commit -m "feat(security_guard): add SecureSessionScope"
```

---

### Task 12: `registerSecurityModule`, full barrel review, lint verification, full suite

**Files:**
- Create: `lib/features/security_guard/di.dart`
- Test: `test/features/security_guard/di_test.dart`
- Create: `docs/verification/2026-09-17-security-guard-lint-verification.md`
- Temporarily modify, then revert: one file per lint rule being verified

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:payment_module/features/security_guard/di.dart';
import 'package:payment_module/features/security_guard/security_guard.dart';

import '../../support/fakes/fake_secure_window.dart';
import '../../support/fakes/fake_security_environment.dart';

void main() {
  late GetIt getIt;

  setUp(() => getIt = GetIt.asNewInstance());
  tearDown(() => getIt.reset());

  test('registers the given fakes as the SecurityEnvironment and SecureWindow singletons', () {
    final environment = FakeSecurityEnvironment();
    final window = FakeSecureWindow();

    registerSecurityModule(getIt, environment: environment, window: window);

    expect(getIt<SecurityEnvironment>(), same(environment));
    expect(getIt<SecureWindow>(), same(window));
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/di_test.dart`
Expected: FAIL to compile — `Target of URI doesn't exist: 'package:payment_module/features/security_guard/di.dart'`

- [ ] **Step 3: Implement**

```dart
// lib/features/security_guard/di.dart
import 'package:get_it/get_it.dart';

import 'security_guard.dart';

/// Registers `security_guard`'s ports with [getIt]. Pass [environment]/[window] to override with
/// fakes in tests. The composition root's real registration (channel adapters) is added by the
/// native-bridge implementation plan; until then this only registers what it's given.
void registerSecurityModule(GetIt getIt, {SecurityEnvironment? environment, SecureWindow? window}) {
  if (environment != null) {
    getIt.registerSingleton<SecurityEnvironment>(environment);
  }
  if (window != null) {
    getIt.registerSingleton<SecureWindow>(window);
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `~/fvm/versions/3.44.6/bin/flutter test test/features/security_guard/di_test.dart`
Expected: `00:00 +1: All tests passed!`

- [ ] **Step 5: Verify the layer lint rules fire, using `dart analyze` (Plan 1's finding — `flutter analyze` will not show these)**

For each pair below: make the edit, run `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`, confirm the named rule appears in the output, then revert the edit.

- `domain_no_flutter`: temporarily add `import 'package:flutter/widgets.dart';` to `lib/features/security_guard/src/domain/security_posture.dart`. Expected: `domain_no_flutter` reported.
- `domain_no_presentation`: temporarily add `import '../presentation/posture_state.dart';` to the same file. Expected: `domain_no_presentation` reported.
- `presentation_no_data`: temporarily add `import '../data/nothing.dart';` to `lib/features/security_guard/src/presentation/posture_state.dart` (the file doesn't need to exist for the *rule* to fire — `import_lint` matches on the glob pattern against the literal import string, not on whether the target resolves; if this doesn't fire because the analyzer refuses to check a rule against an unresolvable import, instead create an empty placeholder `lib/features/security_guard/src/data/.gitkeep`-sibling `nothing.dart` with just a comment, run the check, then delete both the import and the file). Expected: `presentation_no_data` reported.
- `domain_no_data`: symmetric — temporarily add an import from `../data/nothing.dart` (same caveat) to `security_posture.dart`.

`security_guard_via_barrel` and `no_reverse_dependency` remain **not yet verifiable** — `lib/features/payment/` doesn't exist. Verify both in Plan 3, immediately after `features/payment` is created.

- [ ] **Step 6: Confirm the workspace is clean again**

Run: `~/fvm/versions/3.44.6/bin/dart analyze --fatal-infos`
Expected: `No issues found!`

- [ ] **Step 7: Run the full test suite**

Run: `~/fvm/versions/3.44.6/bin/flutter test`
Expected: all tests pass — 21 from Plan 1 plus every test written in Tasks 2–12 of this plan. Count the actual total from the test runner's own summary line rather than trusting an arithmetic estimate (Plan 1's plan document had one such estimate wrong — verify, don't recompute by hand).

- [ ] **Step 8: Check formatting**

Run: `~/fvm/versions/3.44.6/bin/dart format --set-exit-if-changed lib test`
Expected: exit code 0; if not, run `dart format lib test` and re-check.

- [ ] **Step 9: Record the verification**

```markdown
# security_guard lint verification — 2026-09-17

Verified against `docs/architecture.md` §3.3, §4, §5, §7.2, §8, §11.

- `domain_no_flutter`, `domain_no_presentation`, `presentation_no_data`, `domain_no_data`: each
  confirmed firing under `dart analyze --fatal-infos` (temporary violation added, rule name
  observed in the output, reverted).
- `security_guard_via_barrel`, `no_reverse_dependency`: **not yet verifiable** —
  `lib/features/payment/` does not exist. Verify in the payment feature's implementation plan,
  immediately after `features/payment` is created.
- Full suite: `flutter test` — <ACTUAL COUNT from Step 7> tests passing.
- `security_guard` is feature-complete against fakes: domain model, both ports, the one use
  case, `SecurityPostureCubit`, `SecureWindowController`, `SecureSessionScope`, and
  `registerSecurityModule`. No native adapter exists yet — that's the native-bridge plan.
```

(Fill in `<ACTUAL COUNT from Step 7>` with the real number the test runner reported — do not estimate it.)

- [ ] **Step 10: Commit**

```bash
git add lib/features/security_guard test/features/security_guard/di_test.dart docs/verification/2026-09-17-security-guard-lint-verification.md
git commit -m "feat(security_guard): add registerSecurityModule; verify layer lint rules; full suite green"
```

---

## Self-review

**Spec coverage** (against `docs/architecture.md` §4's `features/security_guard` listing, §5, §7.2, §8, §11): domain — `ThreatAssessment`, `AssessmentResult`, `SecurityPosture`, `PolicyVerdict`, `PostureUpdate`, `SecurityBrandConfig` ✓ (Tasks 2–4, 7) · ports `SecurityEnvironment`, `SecureWindow` ✓ (Tasks 5–6) · use case `WatchPostureVerdict` + pure fn `evaluatePosturePolicy` ✓ (Tasks 4, 8) · presentation — `SecurityPostureCubit`, `SecureSessionScope`, `SecureWindowController` ✓ (Tasks 9–11) · registration `registerSecurityModule` ✓ (Task 12) · fakes `FakeSecurityEnvironment`, `FakeSecureWindow` ✓ (Tasks 5–6) · layer + module-wall lint rules ✓ (Task 1 config, Task 12 verification, two rules explicitly deferred with a stated reason). Deliberately deferred, named as such in the Scope Boundary: `SecurityScanView`, `PostureBanner` (a short follow-up plan — substantial ported prototype code, blocks nothing else), the real channel adapters (native-bridge plan).

**Placeholder scan:** no `TBD`/`TODO`/"add error handling"/"similar to Task N" — every code step shows complete code. `registerSecurityModule`'s doc comment explicitly states what it doesn't yet do (register real adapters) and why (a later plan's job), which is a scope note, not an unfinished implementation. Step 9's `<ACTUAL COUNT>` is an explicit instruction to fill in a real, run-verified number, not a placeholder left in the codebase.

**Type consistency:** `PostureUpdate` lives in `policy_verdict.dart` (Task 4) and every task that uses it — Task 8 (`watch_posture_verdict.dart`) and Task 9 (`security_posture_cubit.dart`) — imports it from that one path, consistent with the File Structure section's decision to fold it in there rather than give a two-field tuple its own file. `SecurityPostureCubit`'s constructor parameter order (`environment, policy`) matches `WatchPostureVerdict`'s constructor order everywhere both are used (Tasks 8, 9). `SecureWindowController`'s three methods (`acquire`, `release`, `onResumed`) are named identically in `SecureSessionScope` (Task 11) and its test (Task 10).
