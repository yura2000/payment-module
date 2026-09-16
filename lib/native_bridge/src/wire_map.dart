import '../../core/exceptions.dart';

/// A decoded channel payload, read with type checks. Anything that doesn't match the contract of
/// docs/architecture.md §9 — not a map, a missing or mistyped key, an unknown enum name — throws
/// [TransportException].
final class WireMap {
  WireMap(Object? payload)
    : _map = payload is Map<Object?, Object?>
          ? payload
          : throw TransportException(
              'Expected a map payload, got ${payload.runtimeType}',
            );

  final Map<Object?, Object?> _map;

  String string(String key) => _read<String>(key);

  int integer(String key) => _read<int>(key);

  double decimal(String key) => _read<num>(key).toDouble();

  List<Object?> list(String key) => _read<List<Object?>>(key);

  /// The enum value whose `name` is the string at [key] — wire enums are lowerCamelCase names.
  T enumByName<T extends Enum>(String key, List<T> values) {
    final name = string(key);
    return values.asNameMap()[name] ??
        (throw TransportException('Unknown value "$name" for "$key"'));
  }

  T _read<T>(String key) {
    final value = _map[key];
    if (value is T) return value;
    throw TransportException(
      'Expected "$key" to be $T, got ${value.runtimeType}',
    );
  }
}
