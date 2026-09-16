# 06. Pub workspace mechanics for a Flutter app member

Type: research
Status: resolved
Blocked by: —
Part of: ../map.md

## Question

Exact mechanics of a Pub workspace (Dart ≥ 3.6) with `app/` as a Flutter application member and four packages (`packages/core`, `packages/brand_engine`, `packages/security_guard`, `packages/payment`):

- Root `pubspec.yaml` shape (`workspace:` list, `environment`), `resolution: workspace` in members.
- Where `pubspec.lock` lives (single root lock) and whether to commit it for an app (the repo's `.gitignore` currently ignores it).
- `flutter pub get` from root vs member; running `flutter build apk --flavor retail --dart-define=BRAND=retail` from `app/`.
- Running `flutter test` / `flutter analyze` across all members: root command or loop?
- IDE (VS Code / Android Studio) quirks; FVM interplay (`.fvmrc` at root).

**Deliverable**: exact layout + commands + gotchas.

**Decision waiting on this**: ticket 15 (spec repo-layout section) and the later scaffold step.

## Answer

**Resolved 2026-09-16 by a research agent.** Findings (with a copy-pasteable skeleton: root pubspec, member pubspecs, command list): `docs/research/pub-workspace-flutter.md` on branch `research/pub-workspace-flutter`. Verified against dart.dev / pub issues / Flutter's own repo; not executed.

**Decisions for the spec's repo-layout section**
- Root `pubspec.yaml`: `name: _`, `publish_to: none`, `environment.sdk: ^3.12.0`, `workspace: [app, packages/core, packages/brand_engine, packages/security_guard, packages/payment]`. Every member: `resolution: workspace` + the same SDK floor. One shared resolution — members cannot pin different versions. Intra-workspace deps are plain constraints (`core: ^1.0.0`), never `path:`.
- **One `pubspec.lock` at the root — commit it** (application-style reasoning; upstream dart-lang/pub#4616 is still open, so this is our call). The repo's `.gitignore` currently ignores `pubspec.lock` → remove that line at scaffold time.
- After dependency changes run **both** `dart pub get` (root) and `fvm flutter pub get` inside `app/` — root-only `pub get` historically failed to regenerate `app/android/local.properties` (fixed upstream mid-2025, exact stable release UNVERIFIED — check once on the pinned SDK).
- Everyday commands run from `app/`: `fvm flutter run|build apk --flavor retail --dart-define=BRAND=retail`. `dart format .` and `flutter analyze .` fan out from the root; **`flutter test` does not** — the Makefile loops per member (`dart test` in `core`, `flutter test` in the Flutter members).
- `fvm flutter` inside `app/` finds the root `.fvmrc` (ancestor search — confirmed). Don't run `fvm use` from inside `app/` (may write a nested `.fvmrc` — UNVERIFIED).
- Layout rule: no directory between the root and a member may hold its own `pubspec.yaml` unless it is itself a member — `pub get` hard-fails (mind future `example/` apps).
- `dart pub workspace list` needs Dart ≥ 3.13 — not available on 3.12.2 and *not* independently upgradable (Dart ships with Flutter); the agent's "bump Dart" suggestion is moot. We don't need the command.
- IDE: VS Code Dart-Code workspace support issues are closed; Android Studio test discovery in workspaces (IDEA-374868) UNVERIFIED — check manually.

**Scaffold smoke tests to run** (carry into the scaffold step): root-only `pub get` → does `app/android/local.properties` appear; `flutter build apk --flavor retail` and `--flavor utility` from `app/`; `import_lint` violating-file check (ticket 05).

## Addendum (2026-09-16, after map completion)
The Pub workspace is no longer the starting layout (ADR-0001: single application package, feature-first). These findings are kept as the mechanics for the named scaling path — promoting a feature to `packages/` when a second app or team consumes it.
