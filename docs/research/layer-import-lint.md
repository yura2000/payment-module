# Cross-layer import enforcement inside a package (Ticket 05)

## Question

On Dart 3.12.2 / Flutter 3.44.6 (FVM, Pub workspace: `app/` + `packages/{core,brand_engine,security_guard,payment}`), which tool enforces — with the least ceremony — that inside a feature package's `lib/src/{domain,data,presentation}` folders:

- `domain` imports nothing from `data`, `presentation`, or `package:flutter`
- `presentation` never imports `data`

Candidates: `import_lint`, a hand-rolled `custom_lint` rule, DCM's `avoid-banned-imports`, and a zero-tooling `src/`-privacy + barrel-export convention.

## Short answer

- Use **`import_lint` 2.0.0**: maintained, MIT, pub.dev package.
- Built on Dart's *new* first-party analyzer-plugin system (`analysis_server_plugin`, since Dart 3.10).
- Needs SDK `>=3.10.0 <4.0.0` — Dart 3.12.2 satisfies this.
- Enforcement is pure YAML (`target`/`from`/`except` globs) — zero Dart code, wired into `dart analyze`/IDE.
- `custom_lint` is stale (last published Sept 2025) and rides the *legacy* plugin system.
- dart-lang/sdk confirms that legacy system is deprecated at Dart 3.13.2, naming custom_lint as its primary client — a bad new investment.
- DCM `avoid-banned-imports` is the most expressive rule, but it's a separate, license-gated, closed binary outside `dart analyze`.
- Zero-tooling barrels do **not** work: `implementation_imports` only fires across package boundaries (dart.dev, confirmed).

## Findings

### 1. `import_lint` — maintained, Dart-3.12-ready, declarative

- Latest version **2.0.0**, published **2026-04-18**, SDK constraint `>=3.10.0 <4.0.0` — verified via the pub.dev API (`https://pub.dev/api/packages/import_lint`), not just the rendered page. [pub.dev/packages/import_lint](https://pub.dev/packages/import_lint)
- Its own changelog states v2.0.0 **"Migrated from `analyzer_plugin` to `analysis_server_plugin`"** — i.e. it moved off the legacy plugin foundation (the same one custom_lint still uses) and onto Dart's new official one. Config moved from an `analyzer:` block to the new top-level `plugins:` section, and the rule "is now registered as a warning rule so the plugin is enabled by default (no `diagnostics:` block required)." [CHANGELOG.md](https://github.com/kawa1214/import-lint/blob/main/CHANGELOG.md)
- Dependency list (from the pub.dev API) confirms this directly: `analysis_server_plugin: ^0.3.14`, `analyzer: ^12.1.0`, `glob: ^2.1.3`. [pub.dev API](https://pub.dev/api/packages/import_lint)
- Config shape, per the package README: a top-level `plugins: { import_lint: <version> }` plus an `import_lint:` section with named `rules:`, each taking glob `target` (files being restricted), `from` (banned import patterns), `except` (exceptions), and an optional `severity`. The published example already shows a package-import-URI glob (`from: "package:import_lint/*.dart"`), so banning `package:flutter/**` the same way is a supported pattern, not a stretch. [github.com/kawa1214/import-lint](https://github.com/kawa1214/import-lint)
- License: MIT. [pub.dev/packages/import_lint/license](https://pub.dev/packages/import_lint/license)
- Maintenance signal: small (single/two-maintainer), 33 GitHub stars, repo last pushed 2026-04-18 (the 2.0.0 rewrite), 8 open issues as of today. [github.com/kawa1214/import-lint](https://github.com/kawa1214/import-lint) (via GitHub API)
- The one open issue that matters for adoption risk: **#46**, opened 2026-08-03, still open — import_lint's own `analyzer: ^12.1.0` pin can conflict with other dev-tooling that needs newer analyzer (reporter's case: `drift_dev >=2.34.1` wants `analyzer ^13.0.0`). This is a real, current version-solving risk if import_lint is added as a plain `dev_dependency` alongside code-gen tooling. [github.com/kawa1214/import-lint/issues/46](https://github.com/kawa1214/import-lint/issues/46)
- The other notable issue, **#9** ("VS Code doesn't show warning even though pub command does"), is from 2022, **closed**, and predates the 2.0.0 rewrite — the CLI/IDE split it describes is largely what the analyzer-plugin migration fixes (plugin-reported warnings show in the IDE automatically). Not a live concern. [github.com/kawa1214/import-lint/issues/9](https://github.com/kawa1214/import-lint/issues/9)
- Corroborating evidence the pre-2.0 architecture really was legacy-plugin-based: dart-lang/sdk issue **#59744** (Dec 2024, closed) is an analyzer crash with a stack trace running straight through `package:import_lint/src/plugin/plugin.dart` → `package:analyzer_plugin/plugin/plugin.dart` — the legacy package. [github.com/dart-lang/sdk/issues/59744](https://github.com/dart-lang/sdk/issues/59744)

### 2. `custom_lint` — technically still runs at 3.12.2, but it's a dead end

- Latest version **0.8.1**, published **2025-09-09** (≈12 months stale relative to today). SDK constraint `>=3.0.0 <4.0.0` (loose — doesn't itself block 3.12, but the staleness does matter for a "should we build on this" decision). Verified via `https://pub.dev/api/packages/custom_lint`. [pub.dev/packages/custom_lint](https://pub.dev/packages/custom_lint)
- `custom_lint_builder` shows the same last-publish date, so the whole toolchain has been dormant for a year. [pub.dev/packages/custom_lint_builder](https://pub.dev/packages/custom_lint_builder)
- Dart's own analyzer plugin docs: **"Support for analyzer plugins was added in Dart 3.10."** — this is the *new* system. [dart.dev/tools/analyzer-plugins](https://dart.dev/tools/analyzer-plugins)
- dart-lang/sdk issue **#62164**, "Deprecating the legacy analyzer plugin system" (opened 2025-12-03, **closed 2026-09-02**), states outright: **"the legacy analyzer plugin system, whose primary client was @rrousselGit's `custom_lint`"**, and lays out a plan to deprecate it "as early as Dart 3.12." [github.com/dart-lang/sdk/issues/62164](https://github.com/dart-lang/sdk/issues/62164)
- The follow-up, issue **#64188**, "Remove legacy analyzer plugin system" (opened 2026-09-02, **still open**, unscheduled), confirms the outcome: **"The legacy plugin system was deprecated in Dart 3.13.2."** That is the very next minor release after the project's pinned 3.12.2 — custom_lint is not broken today, but it is one release away from running on officially deprecated infrastructure, with removal already being tracked. [github.com/dart-lang/sdk/issues/64188](https://github.com/dart-lang/sdk/issues/64188)
- By contrast, the *new* system's own package is actively shipping: `analysis_server_plugin` latest **0.3.23**, published **2026-09-11** (5 days before this research), SDK constraint `^3.9.0`. Its changelog includes a **0.3.20** entry fixing "an issue with Dart SDKs <= 3.12.x" where analysis could hang — i.e. the Dart team is actively testing and patching against the project's exact SDK line. [pub.dev/packages/analysis_server_plugin/changelog](https://pub.dev/packages/analysis_server_plugin/changelog)
- Code size for a minimal rule: pub.dev's own custom_lint README example (a `DartLintRule` subclass + `LintCode` + `PluginBase`/`createPlugin`) is about **27 lines** for a trivial rule; swapping the visitor to `context.registry.addImportDirective(...)` and matching `node.uri.stringValue` against banned path patterns would add maybe 10–15 more lines — call it **35–45 lines** all-in. [pub.dev/packages/custom_lint](https://pub.dev/packages/custom_lint)
- Equivalent effort on the *new* plugin system (extend `AnalysisRule` + a `SimpleAstVisitor`, register via `registerNodeProcessors()`, plus the `Plugin`/`PluginRegistry` boilerplate) runs **~40–50 lines** per a walkthrough of the new API, and as of today that system's per-rule configuration is enable/disable only — no arbitrary YAML parameters like custom_lint's, so banned-path patterns would have to be hardcoded in Dart rather than expressed in `analysis_options.yaml`. Secondary source, cross-checked against the primary `analysis_server_plugin`/dart.dev docs' silence on parameterized config. [verygood.ventures blog](https://verygood.ventures/blog/creating-your-first-dart-analyzer-plugin-with-the-new-plugin-system/), [leancode.co blog](https://leancode.co/blog/migrating-to-dart-analyzer-plugin-system)
- **Answering the ticket's sub-question directly**: the official analyzer plugin API has *not yet fully replaced* custom_lint at Dart 3.12.2 (custom_lint still runs), but it is unambiguously the sanctioned forward path, and the legacy foundation custom_lint depends on is deprecated one release later (3.13.2) with removal already tracked. Writing a **new** rule today should target `analysis_server_plugin` directly, or better, use a package already built on it (see `import_lint` above) rather than investing in custom_lint or hand-rolling a new legacy-system plugin.

### 3. DCM `avoid-banned-imports` — most expressive rule, but a separate paid tool

- The rule is purpose-built for exactly this: `entries` list, each with `paths` (regex, where the ban applies), `exclude-paths`, `deny` (regex import patterns to ban), `message`, `severity`. [dcm.dev/docs/rules/common/avoid-banned-imports](https://dcm.dev/docs/rules/common/avoid-banned-imports/)
- DCM is **not** an analyzer plugin — it's a standalone compiled binary invoked as `dcm analyze .`, installed via brew/apt/choco or a direct GitHub-release download, separate from `dart analyze`/`flutter analyze`. The docs did not state a minimum Dart/Flutter SDK version. [dcm.dev/docs/getting-started/for-developers/installation](https://dcm.dev/docs/getting-started/for-developers/installation/)
- Licensing: today's DCM (CQLabs, dcm.dev) is proprietary — distributed as a licensed binary (CI key + email required for automated use), not as inspectable open source. This is a **different codebase** from the old, now-sunset `dart_code_metrics` OSS analyzer plugin (`dart-code-checker/dart-code-metrics`), whose repo is under Business Source License 1.1 with change date **2026-07-16 → MIT** (already flipped, but that predecessor is retired and unrelated to the current product). Don't conflate the two when citing "DCM is open source." [github.com/dart-code-checker/dart-code-metrics LICENSE](https://raw.githubusercontent.com/dart-code-checker/dart-code-metrics/master/LICENSE), [github.com/CQLabs/dcm-action](https://github.com/CQLabs/dcm-action)
- Pricing: **Free** plan, $0, no card, individual use, capped at "up to 50k analyzed LOC" and "100 unique lint rules." **Pro**, $16/month, 536 rules, up to 150k LOC. **Teams**, $80/month for 5–30 seats. [dcm.dev/pricing](https://dcm.dev/pricing/)
- There is also a dedicated free license for OSS maintainers, but DCM's own announcement frames it around "maintainers who are not paid to work on open source" on projects "helpful to other developers in the community," requiring an application (email, project URL, description) — this is aimed at published, community-facing packages, not a one-off interview/demo repo. [dcm.dev/blog/2023/10/18/announcing-dcm-license-for-oss-projects](https://dcm.dev/blog/2023/10/18/announcing-dcm-license-for-oss-projects/)
- **Viability for an open interview repo**: the plain $0 Free tier would almost certainly cover a small repo on the LOC/rule-count limits alone, so it's *usable* — but it adds an external account, a separate binary outside the standard Dart toolchain, and licensing friction that the ticket's "least ceremony" framing weighs against. It is the strongest *rule engine* of the four, weakest on ceremony/openness.

### 4. Zero-tooling: `src/` privacy + barrel exports

- Confirmed **not sufficient**, straight from Dart's own linter docs: the `implementation_imports` rule's purpose is "you don't import implementation files from another **package**," and explicitly: **"You can import libraries from lib/src within other Dart code in the same package"** — it only fires when a *different* package reaches into `lib/src`. Nothing stops `packages/payment/lib/src/presentation/foo.dart` from importing `packages/payment/lib/src/data/bar.dart` directly; both are inside the same package. A barrel file (`lib/payment.dart`) controls the package's **public/exported** surface, but every file under `lib/src/**` can still freely import every other file under `lib/src/**` — barrels do not create internal visibility boundaries. [dart.dev/tools/linter-rules/implementation_imports](https://dart.dev/tools/linter-rules/implementation_imports)
- No first-party linter rule fills this gap. Scanning the full first-party rule catalog, every rule whose name mentions "import" is purely stylistic: `always_use_package_imports`, `avoid_relative_lib_imports`, `implementation_imports`, `prefer_relative_imports` — none express "layer A must not depend on layer B" within one package. [dart.dev/tools/linter-rules/all](https://dart.dev/tools/linter-rules/all)
- The Dart 3.10+ analyzer-plugin system (`analysis_server_plugin`, used by `import_lint`) is the first-party mechanism capable of expressing this, but it requires *someone's* plugin code (hand-rolled, or a ready-made one like `import_lint`) — it is not a built-in rule you can flip on. [dart.dev/tools/analyzer-plugins](https://dart.dev/tools/analyzer-plugins)

## Recommendation

Adopt **`import_lint` 2.0.0** in `packages/payment/analysis_options.yaml` (repeat per feature package). Add it once as a dev dependency and configure purely in YAML:

```yaml
# packages/payment/pubspec.yaml
dev_dependencies:
  import_lint: ^2.0.0   # requires Dart SDK >=3.10.0 <4.0.0 — satisfied by 3.12.2
```

```yaml
# packages/payment/analysis_options.yaml
plugins:
  import_lint: ^2.0.0

import_lint:
  severity: error
  rules:
    domain_no_data:
      target: "package:payment/src/domain/**.dart"
      from: "package:payment/src/data/**.dart"
      except: []

    domain_no_presentation:
      target: "package:payment/src/domain/**.dart"
      from: "package:payment/src/presentation/**.dart"
      except: []

    domain_no_flutter:
      target: "package:payment/src/domain/**.dart"
      from: "package:flutter/**.dart"
      except: []

    presentation_no_data:
      target: "package:payment/src/presentation/**.dart"
      from: "package:payment/src/data/**.dart"
      except: []
```

This is enforced directly by `dart analyze` / `flutter analyze` and surfaces inline in the IDE, with no CLI wrapper step and no Dart code to write or maintain. Config shape confirmed against the package README and its own dependency on `analysis_server_plugin` ^0.3.14, which is itself compatible with Dart 3.12.2 (`^3.9.0` SDK constraint). [github.com/kawa1214/import-lint](https://github.com/kawa1214/import-lint), [pub.dev/api/packages/import_lint](https://pub.dev/api/packages/import_lint), [pub.dev/api/packages/analysis_server_plugin](https://pub.dev/api/packages/analysis_server_plugin)

If the team later wants a stricter/richer rule set across the whole workspace (not just import banning) and is fine paying for it, DCM's `avoid-banned-imports` is the fallback — same intent, regex instead of globs, but a separate licensed binary:

```yaml
# alternative: DCM, separate tool (`dcm analyze .`), not part of `dart analyze`
dcm:
  rules:
    - avoid-banned-imports:
        entries:
          - paths: ['packages/payment/lib/src/domain/.*\.dart']
            deny: ['package:flutter/.*', 'packages/payment/lib/src/data/.*', 'packages/payment/lib/src/presentation/.*']
            message: 'domain must not depend on data, presentation, or Flutter'
            severity: error
          - paths: ['packages/payment/lib/src/presentation/.*\.dart']
            deny: ['packages/payment/lib/src/data/.*']
            message: 'presentation must not depend on data directly'
            severity: error
```
(DCM config shape per its docs; not verified by execution.) [dcm.dev/docs/rules/common/avoid-banned-imports](https://dcm.dev/docs/rules/common/avoid-banned-imports/)

Do **not** rely on `src/` privacy + barrel exports alone, and do not invest in a new `custom_lint` rule.

## Open questions / caveats

- **Not executed.** This worktree's repo is an empty scaffold (only `.gitignore` present; no `packages/payment` exists yet), so neither the `import_lint` snippet nor the DCM snippet above was actually run against real code. Both are built from the vendors' documented config shape, not verified by `dart pub get` + `dart analyze` output. Treat as a strong starting point, verify on first real use.
- **UNVERIFIED**: exact glob dialect for import_lint's `target`/`from`/`except` (it depends on `package:glob ^2.1.3`, the standard dart-lang glob package, but I did not find a spec of exactly which glob syntax subset import_lint applies it with — e.g., whether `**.dart` vs `**/*.dart` is correct). Test the snippet against a throwaway file in each layer before trusting it in CI.
- **Live risk to watch**: import_lint's own `analyzer: ^12.1.0` pin conflicting with other dev-tooling needing newer `analyzer` (open issue [#46](https://github.com/kawa1214/import-lint/issues/46), Aug 2026) — check this against whatever code-gen packages (build_runner, json_serializable, etc.) the other workspace packages already pin before adding import_lint as a plain `dev_dependency` everywhere.
- **UNVERIFIED**: whether the exact pairing "Flutter 3.44.6 / Dart 3.12.2" (given as project fact) has been smoke-tested with import_lint 2.0.0 specifically by anyone other than its 8-open-issue GitHub tracker; no issue found mentioning 3.12 by version number one way or the other.
- Bus-factor: import_lint is a small (33-star), effectively single/two-maintainer package. That's a real dependency-risk trade against DCM's commercially-backed (but paid/closed) alternative — worth a line in the architecture spec if this becomes a long-lived convention rather than an interview-repo one-off.
- Dart 3.12.2 sits one minor release before the legacy analyzer-plugin system's confirmed deprecation point (3.13.2, per [#64188](https://github.com/dart-lang/sdk/issues/64188)). If the workspace upgrades Dart before this decision ships, re-check whether custom_lint has since been abandoned outright (its removal issue was unscheduled as of this research).

## Sources

- [dart.dev — Analyzer plugins](https://dart.dev/tools/analyzer-plugins)
- [dart.dev — implementation_imports lint rule](https://dart.dev/tools/linter-rules/implementation_imports)
- [dart.dev — All linter rules](https://dart.dev/tools/linter-rules/all)
- [dart.dev — Announcing Dart 3.12](https://dart.dev/blog/announcing-dart-3-12)
- [github.com/dart-lang/sdk issue #62164 — Deprecating the legacy analyzer plugin system](https://github.com/dart-lang/sdk/issues/62164)
- [github.com/dart-lang/sdk issue #64188 — Remove legacy analyzer plugin system](https://github.com/dart-lang/sdk/issues/64188)
- [github.com/dart-lang/sdk issue #59744 — ErrorResult lib path is required (legacy analyzer_plugin crash via import_lint)](https://github.com/dart-lang/sdk/issues/59744)
- [pub.dev/packages/import_lint](https://pub.dev/packages/import_lint) and [pub.dev/api/packages/import_lint](https://pub.dev/api/packages/import_lint) (JSON: version, SDK constraint, dependencies)
- [pub.dev/packages/import_lint/license](https://pub.dev/packages/import_lint/license)
- [github.com/kawa1214/import-lint](https://github.com/kawa1214/import-lint) (README, config shape)
- [github.com/kawa1214/import-lint/blob/main/CHANGELOG.md](https://github.com/kawa1214/import-lint/blob/main/CHANGELOG.md)
- [github.com/kawa1214/import-lint/issues/46](https://github.com/kawa1214/import-lint/issues/46) (open, analyzer version conflict)
- [github.com/kawa1214/import-lint/issues/9](https://github.com/kawa1214/import-lint/issues/9) (closed, pre-2.0 IDE issue)
- [pub.dev/packages/custom_lint](https://pub.dev/packages/custom_lint) and [pub.dev/api/packages/custom_lint](https://pub.dev/api/packages/custom_lint)
- [pub.dev/packages/custom_lint/changelog](https://pub.dev/packages/custom_lint/changelog)
- [pub.dev/packages/custom_lint_builder](https://pub.dev/packages/custom_lint_builder)
- [pub.dev/packages/analysis_server_plugin/changelog](https://pub.dev/packages/analysis_server_plugin/changelog) and [pub.dev/api/packages/analysis_server_plugin](https://pub.dev/api/packages/analysis_server_plugin)
- [dcm.dev/docs/rules/common/avoid-banned-imports](https://dcm.dev/docs/rules/common/avoid-banned-imports/)
- [dcm.dev/docs/getting-started/for-developers/installation](https://dcm.dev/docs/getting-started/for-developers/installation/)
- [dcm.dev/pricing](https://dcm.dev/pricing/)
- [dcm.dev/blog/2023/10/18/announcing-dcm-license-for-oss-projects](https://dcm.dev/blog/2023/10/18/announcing-dcm-license-for-oss-projects/)
- [github.com/dart-code-checker/dart-code-metrics LICENSE (BSL 1.1, predecessor OSS project)](https://raw.githubusercontent.com/dart-code-checker/dart-code-metrics/master/LICENSE)
- [github.com/CQLabs/dcm-action](https://github.com/CQLabs/dcm-action)
- Secondary (used only for code-size estimate on the new plugin API, cross-checked against primary docs' silence on the same point): [Very Good Ventures — Creating Your First Dart Analyzer Plugin](https://verygood.ventures/blog/creating-your-first-dart-analyzer-plugin-with-the-new-plugin-system/), [LeanCode — Migrate to the New Dart Analyzer Plugin System](https://leancode.co/blog/migrating-to-dart-analyzer-plugin-system)
