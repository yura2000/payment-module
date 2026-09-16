# Pub workspace mechanics for a Flutter app member

## Question

Exact mechanics of a Pub workspace (Dart ≥ 3.6) with `app/` as a **Flutter application** member
and four packages (`packages/core` pure Dart, `packages/brand_engine`, `packages/security_guard`,
`packages/payment` Flutter packages): root/member `pubspec.yaml` shape, `pubspec.lock` location
and commit policy, `flutter pub get`/`build`/`run` behavior from root vs. member, how to
test/analyze/format across all members, IDE quirks, and FVM's `.fvmrc` discovery when the app
lives in a subdirectory.

Project facts assumed: Flutter 3.44.6 / Dart 3.12.2 via FVM, Android flavors `retail` and
`utility`, Java 17.

## Short answer

- Root `pubspec.yaml`: `name` + `workspace: [app, packages/core, ...]` + `environment.sdk: ^3.6.0+`.
- Every member adds `resolution: workspace` and the same SDK floor — pure-Dart `packages/core` included.
- One shared resolution for the whole workspace: members cannot pin different dependency versions.
- Cross-member deps are plain version constraints (`core: ^1.0.0`), not `path:`; pub resolves them locally regardless.
- Exactly one `pubspec.lock`, at the workspace root — commit it (app-style), but this repo's `.gitignore` currently hides it, and the general "commit for a workspace whose root isn't the app" question is still an open, unresolved dart-lang/pub issue.
- Run `flutter pub get` from **both** root and `app/` — root-only `pub get` has a documented history of not regenerating `app/android/local.properties`/`Generated.xcconfig` (fixed mid-2025 upstream; verify on your pinned SDK).
- No root-level `flutter test`; `dart format .` / `flutter analyze .` do fan out workspace-wide, but tests must be looped per member.
- `dart pub workspace list` needs Dart ≥ 3.13.0 — one release ahead of the pinned 3.12.2.
- FVM's ancestor-directory search means `fvm flutter`/`fvm dart` run inside `app/` automatically pick up the root `.fvmrc`.

## Findings

### 1. Root and member `pubspec.yaml` shape; shared resolution; intra-workspace deps

Pub workspaces (a "single shared dependency resolution for all your packages") were introduced in
**Dart 3.6.0**. The root `pubspec.yaml` needs a `name`, a `workspace` list of member paths, and an
`environment.sdk` constraint of `^3.6.0` or higher; the official example uses `name: _` and
`publish_to: none`:

```yaml
name: _
publish_to: none
environment:
  sdk: ^3.6.0
workspace:
  - packages/shared
  - packages/client_package
  - packages/server_package
```

Every member adds `resolution: workspace` and must itself declare an SDK constraint of at least
`^3.6.0` — this applies to pure-Dart members exactly like Flutter ones; there's no exemption for
`packages/core`.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

`name` on the root is **required** (not optional) — the root is itself a real package inside the
workspace: `dart pub workspace list` prints it as package `_` at path `./` in the official example
output. Flutter's own repo dogfoods this exact shape at its root — `name: _flutter_packages`,
`environment.sdk: ^3.13.0-0`, and a `workspace:` list mixing pure-Dart dev-tooling packages with
Flutter packages side by side, confirming mixed Dart/Flutter membership is fully supported.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces),
[github.com/flutter/flutter/blob/master/pubspec.yaml](https://github.com/flutter/flutter/blob/master/pubspec.yaml)

**Members cannot pin different dependency versions** — confirmed directly: "Using a single shared
dependency resolution for all your packages increases the risks of dependency conflicts, because
Dart doesn't allow multiple versions of the same package," and for `dependency_overrides`: "You can
only override a package once in the workspace. To keep overrides organized, it's preferable to keep
`dependency_overrides` in the root `pubspec.yaml`."
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

**Cross-member dependencies use a plain version constraint, not `path:`.** If
`packages/payment/pubspec.yaml` depends on `core: ^1.0.0`, "the _local_ version of `shared` [core]
will be used" whenever resolved inside the workspace, "regardless of the source" declared — the
local copy still has to satisfy the stated constraint. A `path:` dependency would also resolve
locally (workspace resolution overrides source selection for members), but the plain-constraint
form is what the docs show and is more robust: if `payment` is ever published or otherwise consumed
*outside* the workspace, the same constraint falls back to fetching `core` from pub.dev/hosted,
whereas a `path:` constraint would simply break for external consumers.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

**Layout hazard:** if any directory *between* the workspace root and a member contains its own
stray `pubspec.yaml` that is not itself a listed workspace member (or a nested workspace root),
`dart pub get` errors out rather than resolving. A workspace member may itself declare a nested
`workspace:` field (e.g., if `packages/payment` later grows its own sub-packages), in which case
the root only needs to list `packages/payment` and pub discovers its children automatically.
Glob patterns (`workspace: [packages/*]`) are supported but need Dart **≥ 3.11**.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

To scope a pub command to one member without `cd`-ing: `dart pub -C packages/payment publish`.
To resolve a single member independently of the workspace (e.g., to sanity-check its own
constraints before publishing), drop a `packages/payment/pubspec_overrides.yaml` containing
`resolution:` (empty), then `dart pub get` inside that directory.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

### 2. `pubspec.lock` location and commit policy

There is exactly **one** `pubspec.lock`, written next to the root `pubspec.yaml`. Running
`dart pub get` anywhere in the repo deletes any other `pubspec.lock` (and
`.dart_tool/package_config.json`) found next to member packages or in directories between the root
and a member — these are called "stray files" in the docs.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

General Dart guidance (not workspace-specific): "For application packages, we recommend that you
commit the `pubspec.lock` file. Versioning the `pubspec.lock` file ensures changes to transitive
dependencies are explicit." Conversely, "don't commit the `pubspec.lock` file [for library
packages]. Regenerating the `pubspec.lock` file lets you test your package against the latest
compatible versions of its dependencies." This page does not mention workspaces at all — it
pre-dates/ignores the one-lock-for-a-mixed-repo case.
[dart.dev/tools/pub/private-files](https://dart.dev/tools/pub/private-files)

**This exact ambiguity — one shared lock, but the workspace mixes an app and several libraries —
is an open, unresolved issue with the dart-lang/pub team as of this research** (filed July 2025,
still open, no maintainer consensus posted). The issue author's own leaning: commit the workspace
lock, reasoning that "the workspace lock is inconsequential for packages when they are used as
dependencies" by someone outside the repo (a consumer never reads your repo's `pubspec.lock` for
its own transitive resolution — only your root/app's lock matters when *you* build). An alternative
of copying the lock next to each `pubspec.yaml` was raised and called out in-thread as "weird."
[github.com/dart-lang/pub/issues/4616](https://github.com/dart-lang/pub/issues/4616)

**Repo-specific note:** this worktree's `.gitignore` (Dart's stock community template — same header
comment `# See https://www.dartlang.org/guides/libraries/private-files`) currently ends with:

```
# If you're building an application, you may want to check-in your pubspec.lock
pubspec.lock
```

That comment/rule pair is a known, longstanding self-contradiction in the stock Dart/Flutter
`.gitignore` template itself (the comment recommends committing, the line still ignores it) — it is
not something specific to this repo or to workspaces.
[github.com/github/gitignore/blob/main/Dart.gitignore](https://github.com/github/gitignore/blob/main/Dart.gitignore)

### 3. `flutter pub get` / `flutter build` / `flutter run` — root vs. member

Running `dart pub get`/`flutter pub get` from **anywhere in the workspace** resolves dependencies
for **every** member at once and writes the single root lock + shared `.dart_tool/package_config.json`.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

**Gotcha, confirmed via two linked flutter/flutter issues:** running `flutter pub get` only at the
workspace root has not reliably triggered the *Flutter-tool-specific* post-processing that a
Flutter app needs — regenerating `app/android/local.properties`, `app/ios/Flutter/Generated.xcconfig`,
and (for add-to-app) native `.android`/`.ios` folders. Symptom: Gradle fails with
`local.properties (No such file or directory)`.
[github.com/flutter/flutter/issues/167101](https://github.com/flutter/flutter/issues/167101),
[github.com/flutter/flutter/issues/161927](https://github.com/flutter/flutter/issues/161927)
(#167101 closed as a duplicate of #161927, filed against Flutter 3.27/3.28). It was fixed by
["Run pub get post-processing for each package in workspace"](https://github.com/flutter/flutter/pull/170517),
merged to `flutter:master` **2025-06-23**. UNVERIFIED which stable release first shipped that
commit — I could not pin an exact version number/milestone — but it predates the project's pinned
3.44.6 by a comfortable margin, so it should already be fixed. **Recommendation regardless:**
always run `flutter pub get` once at the root *and* once inside `app/` after touching any
dependency, and treat a missing `app/android/local.properties` after that as a real bug to report,
not a workflow you need to route around.

I found no additional, `--flavor`-specific workspace issue beyond the general one above — the
Gradle failure is about the missing `local.properties`/native scaffolding regardless of which
flavor or `--dart-define` values are passed. Once `app/android/local.properties` exists,
`flutter build apk --flavor retail --dart-define=BRAND=retail` and `flutter run --flavor retail
--dart-define=BRAND=retail` run from `app/` exactly as they would outside a workspace — flavors are
Gradle `productFlavors` / Xcode scheme concepts the workspace layer doesn't touch.

**Code generation (`flutter_gen`/asset resolution):** the community FlutterGen package documents
first-class Pub-workspace support itself: run `build_runner` from the workspace root, ensure each
member that needs generation has `resolution: workspace`, and it "resolves each package from the
active build target instead of the process working directory, so package-local `pubspec.yaml`
configuration and output paths continue to work in workspace builds." This needs Dart `>=3.7.0`
with `build_runner >=2.12.0` (both satisfied by the pinned 3.12.2). Commands:
`dart run build_runner build --workspace` and, for the standalone `fluttergen` CLI,
`fluttergen --workspace -c pubspec.yaml`.
[github.com/FlutterGen/flutter_gen README, "Pub workspaces" section](https://github.com/FlutterGen/flutter_gen/blob/main/README.md)

### 4. Testing / analysis / formatting across all members

No root-level pub subcommand runs `flutter test`/`dart test` across every member — the `pub`
command reference lists `add cache deps downgrade get global outdated publish remove token unpack
upgrade` plus workspace-scoped helpers, nothing that fans out `test`.
[dart.dev/tools/pub/cmd](https://dart.dev/tools/pub/cmd)

What **does** work workspace-wide from the root: `dart format .` (pure filesystem walk, unrelated
to pub) and `flutter analyze .` / `dart analyze .` — because a workspace gives the analyzer one
shared analysis context instead of one per package (this is the whole point of the feature: "If you
open the root folder in your IDE, the dart analyzer will create separate analysis contexts for each
package, increasing memory usage" is exactly what workspaces fix). Each file is still checked
against its own nearest `analysis_options.yaml`.
[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces)

`flutter test`/`dart test`, however, operate on a single "current package" (nearest `pubspec.yaml`)
and do not recurse into member packages from the root. There is no `dart pub workspace test` or
equivalent. You loop per member, and — since `packages/core` is pure Dart while the other three are
Flutter packages — you must use the right runner per member (`dart test` for `packages/core`,
`flutter test` for the rest and for `app/`); running `flutter test` inside a package that has no
`flutter` SDK dependency simply errors. This loop is exactly the gap that monorepo tools like Melos
exist to paper over with one aggregate command — Pub workspaces give you the shared *resolution*,
not an aggregate *test runner*. No root-level Flutter/Dart-provided command closes this gap as of
this research.

`dart pub workspace list` enumerates members (name + path, with `--json` output support):

```
$ dart pub workspace list
Package         Path
_               ./
client_package  packages/client_package/
server_package  packages/server_package/
shared          packages/shared/
```

[dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces). **This command needs Dart
≥ 3.13.0** — confirmed via the Dart SDK changelog entry "Added `dart pub workspace list` command to
list all packages in the workspace along with their directory paths, with support for JSON output
via `--json`," which sits under the `## 3.13.0` header, released **2026-08-12**.
[raw CHANGELOG.md, dart-lang/sdk](https://raw.githubusercontent.com/dart-lang/sdk/main/CHANGELOG.md),
[dart.dev/changelog](https://dart.dev/changelog). **The project's pinned Dart is 3.12.2** (released
2026-05-18, one minor version earlier) — `dart pub workspace list` will not exist on the pinned SDK
until you bump the FVM pin to 3.13+.

### 5. IDE quirks (VS Code Dart-Code, Android Studio/IntelliJ)

VS Code's Dart-Code extension added and iterated on Pub-workspace support across several 2024–2025
releases, closing out the rough edges found so far:
- [Dart-Code#5067 "Support Pub workspaces"](https://github.com/Dart-Code/Dart-Code/issues/5067) —
  closed, milestone v3.94.0: "Using Pub Workspaces no longer results in spurious notifications of
  needing to run `pub get` because projects don't have their own `.dart_tool/package_config.json`
  file." [dartcode.org/releases/v3-94](https://dartcode.org/releases/v3-94/)
- [Dart-Code#5260](https://github.com/Dart-Code/Dart-Code/issues/5260) — dependency-tree view didn't
  understand that "the solve is for all packages in the Pub Workspace and not the one where we
  executed `pub get`"; closed.
- [Dart-Code#5775](https://github.com/Dart-Code/Dart-Code/issues/5775) — Widget Preview scanning
  behavior for multi-project workspaces; closed, milestone v3.124.0.

Given the project's Flutter/Dart versions are current, a reasonably up-to-date Dart-Code build
should not hit these. I did not find an open Dart-Code issue specific to *test discovery/running*
inside a workspace.

Android Studio / IntelliJ (JetBrains Dart plugin) has an open-looking YouTrack ticket,
**IDEA-374868, "Dart test not recognized with pub workspace"** — title only; the YouTrack page is a
JS-rendered SPA my fetch tooling could not scrape, so status/workaround are **UNVERIFIED**. Treat
test-runner integration (the green "run test" gutter icons) as the most likely soft spot in Android
Studio specifically, and verify it manually against the actual `app/` + `packages/*` layout before
relying on it for the team's workflow.
[youtrack.jetbrains.com/issue/IDEA-374868](https://youtrack.jetbrains.com/issue/IDEA-374868)

### 6. FVM and `.fvmrc` discovery

FVM's documented SDK-resolution order for `fvm flutter`/`fvm dart` is: **(1) project `.fvmrc`
file, (2) ancestor-directory `.fvmrc`, (3) global version (`fvm global`), (4) system-PATH Flutter.**
Since `app/` has no `.fvmrc` of its own, step 2 applies and `fvm flutter`/`fvm dart` run from inside
`app/` **will** walk up and pick up the repo-root `.fvmrc`, using the pinned 3.44.6.
[fvm.app/documentation/guides/running-flutter](https://fvm.app/documentation/guides/running-flutter)

FVM's monorepo guide, however, only documents this pattern in terms of plain "subfolder" projects
and **Melos**-based monorepos specifically — `fvm use` auto-detects a `melos.yaml` in the current or
parent directories (up to the git root) and updates its `sdkPath`. It says nothing about Pub
workspaces (no `pubspec.yaml`/`workspace:`-aware detection is documented).
[fvm.app/documentation/guides/monorepo](https://fvm.app/documentation/guides/monorepo). Practical
consequence (reasoned from the above, not separately confirmed): *reading* the version
(`fvm flutter ...` invocations) works transparently from `app/` via ancestor search regardless of
Melos vs. plain Pub workspace; but *writing* a version (`fvm use <version>` run from inside `app/`)
has no workspace-aware redirect to the root and will most likely create/update a new local
`app/.fvmrc` instead of the root one, since only `melos.yaml` presence is documented as triggering
root-aware behavior. Always run `fvm use` at the repo root, not from inside `app/`.

## Recommendation

Adopt the shape the primary docs and Flutter's own repo both use. Copy-pasteable skeleton:

**Root `pubspec.yaml`:**
```yaml
name: _
publish_to: none
environment:
  sdk: ^3.12.0        # match the FVM-pinned Dart; must be >= ^3.6.0 to use workspaces at all
workspace:
  - app
  - packages/core
  - packages/brand_engine
  - packages/security_guard
  - packages/payment
```

**`packages/core/pubspec.yaml`** (pure Dart member):
```yaml
name: core
publish_to: none
environment:
  sdk: ^3.12.0
resolution: workspace

dev_dependencies:
  test: ^1.25.0
```

**`packages/payment/pubspec.yaml`** (Flutter package member, depends on `core`):
```yaml
name: payment
publish_to: none
environment:
  sdk: ^3.12.0
  flutter: ">=3.44.0"
resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  core: ^1.0.0          # plain version constraint — resolves to the local packages/core

dev_dependencies:
  flutter_test:
    sdk: flutter
```

**`app/pubspec.yaml`** (the Flutter application member):
```yaml
name: app
publish_to: none
environment:
  sdk: ^3.12.0
  flutter: ">=3.44.0"
resolution: workspace

dependencies:
  flutter:
    sdk: flutter
  core: ^1.0.0
  brand_engine: ^1.0.0
  security_guard: ^1.0.0
  payment: ^1.0.0

flutter:
  uses-material-design: true
```

**Command list:**
```sh
# After touching any member's dependencies — run BOTH:
dart pub get                    # from repo root: resolves the whole workspace, writes /pubspec.lock
(cd app && fvm flutter pub get) # from app/: also regenerates local.properties / Generated.xcconfig
                                 # (flutter/flutter#167101, #161927 — verify these files appear)

# Everyday app commands — unchanged, run from app/
cd app
fvm flutter run   --flavor retail --dart-define=BRAND=retail
fvm flutter build apk --flavor retail --dart-define=BRAND=retail

# Inspect the workspace (needs Dart >= 3.13 — NOT on the pinned 3.12.2 yet)
dart pub workspace list

# Format / analyze — these DO fan out across all members from root
dart format .
flutter analyze .

# Test — no aggregate command; loop per member with the right runner
fvm dart test                          # from packages/core (pure Dart)
(cd packages/brand_engine   && fvm flutter test)
(cd packages/security_guard && fvm flutter test)
(cd packages/payment        && fvm flutter test)
(cd app                     && fvm flutter test)
```

Layout rule to enforce in the scaffold step: **no directory between the repo root and any member
may contain its own `pubspec.yaml` unless that directory is itself a listed member** (or a nested
workspace root) — `dart pub get` hard-fails otherwise. Keep this in mind before adding any
`example/` app under a package later.

On `pubspec.lock`: commit the single root lock file, and fix the worktree's `.gitignore` so it no
longer ignores it (the file currently ends with `pubspec.lock` on its own line, silently discarding
the one lock that matters for `app/`'s reproducible builds) — this is a recommendation to act on
separately, not something this research branch touches. This follows the general "commit for
applications" guidance and the reasoning in the still-open dart-lang/pub#4616 thread; there is no
settled official workspace-specific guidance to fall back on instead.

Bump the FVM-pinned Dart to `3.13+` (still compatible with Flutter 3.44.6's Dart SDK requirement —
verify against the specific Flutter patch) before depending on `dart pub workspace list` in any
scripts or docs; on 3.12.2 it does not exist.

## Open questions / caveats

- **UNVERIFIED** — the exact Flutter stable version that first included PR #170517's fix for
  missing `local.properties`/`Generated.xcconfig`/native folders after a workspace `pub get`. I
  could not find a version/milestone label on the PR or a bot backport comment; only that it merged
  to `master` 2025-06-23, well before the project's pinned 3.44.6. Verify directly: run
  `flutter pub get` only at the root on a clean checkout and confirm
  `app/android/local.properties` appears without a follow-up `flutter pub get` inside `app/`.
- **UNVERIFIED** — current status/workaround for JetBrains YouTrack IDEA-374868 ("Dart test not
  recognized with pub workspace"); the tracker page did not render for my fetch tooling. Worth a
  manual check in Android Studio before committing the team to it for test running.
- **Reasoned, not directly confirmed** — that `fvm use <version>` run from inside `app/` creates a
  local `app/.fvmrc` rather than updating the root one. FVM's docs confirm ancestor-search for
  *reading* the pinned version and confirm root-aware *writing* only for Melos monorepos; I did not
  find an explicit statement (doc or issue) about `fvm use`'s write-path behavior in a plain Pub
  workspace specifically. Cheap to verify directly: run `fvm use 3.44.6` from `app/` in a scratch
  clone and check whether the root `.fvmrc` changes or a new one appears in `app/`.
- No `--flavor`-specific (as opposed to the general local.properties) workspace bug was found in
  flutter/flutter's issue tracker; absence of evidence, not proof of absence — worth a quick smoke
  build (`flutter build apk --flavor retail`, `--flavor utility`) once the scaffold exists.
- `dart-lang/pub#4616` (pubspec.lock commit policy for mixed app+library workspaces) is open with
  no maintainer resolution — the Recommendation above is this research's own reasoned call, not
  settled upstream guidance. Revisit if that issue resolves differently.

## Sources

- [dart.dev/tools/pub/workspaces](https://dart.dev/tools/pub/workspaces) — canonical Pub workspaces reference (root/member shape, SDK constraints, glob patterns, nested workspaces, stray files, interdependencies, dependency_overrides, `-C`, `pubspec_overrides.yaml` reset trick, `dart pub workspace list`)
- [dart.dev/tools/pub/private-files](https://dart.dev/tools/pub/private-files) — "what not to commit" / pubspec.lock guidance for apps vs. libraries
- [dart.dev/tools/pub/cmd](https://dart.dev/tools/pub/cmd) — full `pub` subcommand list
- [dart.dev/changelog](https://dart.dev/changelog) and [raw CHANGELOG.md, dart-lang/sdk](https://raw.githubusercontent.com/dart-lang/sdk/main/CHANGELOG.md) — confirms `dart pub workspace list` added in Dart 3.13.0 (2026-08-12); confirms 3.12.0 released 2026-05-18
- [github.com/flutter/flutter/blob/master/pubspec.yaml](https://github.com/flutter/flutter/blob/master/pubspec.yaml) — Flutter's own repo as a live example of a mixed Dart/Flutter workspace root
- [github.com/dart-lang/pub/issues/4616](https://github.com/dart-lang/pub/issues/4616) — open issue: pubspec.lock commit policy for workspaces mixing apps and libraries
- [github.com/flutter/flutter/issues/167101](https://github.com/flutter/flutter/issues/167101) — local.properties/Generated.xcconfig not regenerated after workspace `pub get` (closed as duplicate)
- [github.com/flutter/flutter/issues/161927](https://github.com/flutter/flutter/issues/161927) — native folders not created for workspace members on `pub get` (closed, fixed by #170517)
- [github.com/flutter/flutter/pull/170517](https://github.com/flutter/flutter/pull/170517) — "Run pub get post-processing for each package in workspace" (merged 2025-06-23)
- [github.com/flutter/flutter/issues/160477](https://github.com/flutter/flutter/issues/160477) — `resolution: workspace` without a discoverable workspace root fails `pub get` (closed, not a bug — reinforces the stray-pubspec rule)
- [github.com/FlutterGen/flutter_gen/blob/main/README.md](https://github.com/FlutterGen/flutter_gen/blob/main/README.md) — FlutterGen's own documented Pub-workspace support, `--workspace` flag, min Dart/build_runner versions
- [github.com/github/gitignore/blob/main/Dart.gitignore](https://github.com/github/gitignore/blob/main/Dart.gitignore) — source of the stock `pubspec.lock`-ignoring template this repo's `.gitignore` matches
- [fvm.app/documentation/guides/running-flutter](https://fvm.app/documentation/guides/running-flutter) — FVM SDK resolution order (project → ancestor `.fvmrc` → global → PATH)
- [fvm.app/documentation/guides/monorepo](https://fvm.app/documentation/guides/monorepo) — FVM's Melos-focused monorepo guidance (no Pub-workspace-specific mention)
- [github.com/Dart-Code/Dart-Code/issues/5067](https://github.com/Dart-Code/Dart-Code/issues/5067), [dartcode.org/releases/v3-94](https://dartcode.org/releases/v3-94/), [github.com/Dart-Code/Dart-Code/issues/5260](https://github.com/Dart-Code/Dart-Code/issues/5260), [github.com/Dart-Code/Dart-Code/issues/5775](https://github.com/Dart-Code/Dart-Code/issues/5775) — VS Code Dart-Code extension's Pub-workspace support history (all closed)
- [youtrack.jetbrains.com/issue/IDEA-374868](https://youtrack.jetbrains.com/issue/IDEA-374868) — "Dart test not recognized with pub workspace" (title only — UNVERIFIED status, page not scrapable)
