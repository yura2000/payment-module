---
status: accepted
date: 2026-09-16
supersedes: the Pub-workspace decision taken while charting (wayfinder ticket 13, map Notes), revised after review
---
# One application package, feature-first; module walls enforced by lint, packages named as the scaling path

The task grades "clean, modular" and "how easily can we add a 3rd or 4th brand". We keep a single Flutter application
package and give it a feature-first layout — `lib/core`, `lib/brand_engine`, `lib/features/{security_guard, payment}`
(each with a barrel, a private `src/{domain, data, presentation}` and a `di.dart`), and a composition root in
`lib/app`, `lib/brands`, `lib/bootstrap` — with **both** the layer rules and the module dependency DAG enforced by
`import_lint` and a regex architecture test. We considered, and for a while chose, a Pub workspace with one package per
module: it makes dependency direction a declared fact, but it does not remove the need for the layer lint, its unique
benefit is small across four modules, and its tooling (double `pub get`, no root `flutter test`, unverified IDE and flavor
behaviour) would sit on the critical path of a time-boxed deliverable for no visible product value.

## Considered options

- **Pub workspace, one package per module** — the scaling path, deliberately not the start. Trigger to revisit: a second
  app or team consumes `brand_engine`, or a module needs its own release cadence. Mechanics are already researched in
  `docs/research/pub-workspace-flutter.md`; every feature has the package shape today, so extraction is a move plus a
  `pubspec.yaml`.
- **Melos** — unnecessary once Dart has native workspaces.

## Consequences

- Boundaries are lint-enforced, not declared: a rule can be ignored. The architecture test in CI and the "used only through
  its barrel" rule make that a deliberate, visible act rather than an accident.
- Everything a reviewer reads is under one `lib/`; the folder tree communicates the architecture.
