import 'dart:convert';
import 'dart:io';

/// Loads `contract/fixtures/<name>.json` — the same files the Kotlin JVM tests read, so both sides
/// of the bridge are pinned to one set of payloads (docs/architecture.md §9, §14).
Map<String, Object?> contractFixture(String name) =>
    jsonDecode(File('contract/fixtures/$name.json').readAsStringSync())
        as Map<String, Object?>;
