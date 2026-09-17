// §3.3's second enforcement path. `import_lint` is the primary one, but it runs only under
// `dart analyze --fatal-infos` and has silently no-opped before — so the same rules are checked
// here, in plain Dart, from the same source of truth.
import 'dart:io';

import 'package:glob/glob.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _package = 'payment_module';

class _Rule {
  const _Rule(this.name, this.target, this.from, this.except);

  final String name;
  final String target;
  final String from;
  final List<String> except;

  bool targets(String uri) => Glob(target).matches(uri);
  bool forbids(String uri) => Glob(from).matches(uri) && !except.contains(uri);
}

List<_Rule> _loadRules() {
  final yaml = loadYaml(File('analysis_options.yaml').readAsStringSync());
  final rules = (yaml as YamlMap)['import_lint']['rules'] as YamlMap;
  return [
    for (final entry in rules.entries)
      _Rule(
        entry.key as String,
        (entry.value as YamlMap)['target'] as String,
        (entry.value as YamlMap)['from'] as String,
        [
          for (final item in ((entry.value as YamlMap)['except'] as YamlList?) ?? const [])
            item as String,
        ],
      ),
  ];
}

/// `lib/features/payment/src/x.dart` → `package:payment_module/features/payment/src/x.dart`
String _packageUri(File file) {
  final relative = file.path
      .replaceFirst(RegExp(r'^\.?/?lib/'), '')
      .replaceAll(r'\', '/');
  return 'package:$_package/$relative';
}

/// Every `import '...'` in [source], as an absolute URI resolved against [fileUri].
Iterable<String> _imports(String fileUri, String source) => RegExp(
  r'''^\s*import\s+['"]([^'"]+)['"]''',
  multiLine: true,
).allMatches(source).map((match) {
  final raw = match.group(1)!;
  if (raw.startsWith('dart:') || raw.startsWith('package:')) return raw;
  return Uri.parse(fileUri).resolve(raw).toString();
});

void main() {
  final rules = _loadRules();

  test('analysis_options.yaml declares the rules this test enforces', () {
    expect(rules, isNotEmpty);
    // Guards against a silent config rewrite: §3.3 fixes these names.
    expect(
      rules.map((rule) => rule.name),
      containsAll([
        'core_is_flutter_free',
        'core_depends_on_nothing',
        'engine_knows_no_features',
        'domain_no_data',
        'domain_no_presentation',
        'domain_no_flutter',
        'presentation_no_data',
        'security_guard_via_barrel',
        'no_reverse_dependency',
      ]),
    );
  });

  test('every rule declares an explicit except list', () {
    // Without `except: []` the plugin throws while parsing its own config, and under the wrong
    // analyze command that failure is silently swallowed.
    final yaml = loadYaml(File('analysis_options.yaml').readAsStringSync());
    final raw = (yaml as YamlMap)['import_lint']['rules'] as YamlMap;
    for (final entry in raw.entries) {
      expect(
        (entry.value as YamlMap).containsKey('except'),
        isTrue,
        reason: 'rule "${entry.key}" is missing `except: []`',
      );
    }
  });

  test('no file under lib/ imports across a wall', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(files, isNotEmpty, reason: 'run this test from the package root');

    final violations = <String>[];
    for (final file in files) {
      final uri = _packageUri(file);
      final source = file.readAsStringSync();
      for (final rule in rules.where((rule) => rule.targets(uri))) {
        for (final import in _imports(uri, source)) {
          if (rule.forbids(import)) {
            violations.add('${rule.name}: $uri imports $import');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'boundary violations:\n${violations.join('\n')}',
    );
  });

  test('the walker actually matches something — it is not vacuously green', () {
    // A rule set that matches no files would make the test above pass no matter what the code
    // does. Assert the two most load-bearing rules really cover real files.
    final core = 'package:$_package/core/money.dart';
    final payment = 'package:$_package/features/payment/src/presentation/can_pay.dart';

    expect(
      rules.where((rule) => rule.name == 'core_is_flutter_free').single.targets(core),
      isTrue,
    );
    expect(
      rules
          .where((rule) => rule.name == 'security_guard_via_barrel')
          .single
          .targets(payment),
      isTrue,
    );
    expect(
      rules
          .where((rule) => rule.name == 'security_guard_via_barrel')
          .single
          .forbids('package:$_package/features/security_guard/src/domain/policy_verdict.dart'),
      isTrue,
    );
  });
}
