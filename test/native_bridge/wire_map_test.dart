import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';
import 'package:payment_module/core/threat.dart';
import 'package:payment_module/native_bridge/native_bridge.dart';

void main() {
  final wire = WireMap(<Object?, Object?>{
    'name': 'retail',
    'count': 3,
    'rate': 120,
    'items': [1, 2],
    'kind': 'screenRecording',
  });

  test('reads typed values', () {
    expect(wire.string('name'), 'retail');
    expect(wire.integer('count'), 3);
    expect(wire.decimal('rate'), 120.0);
    expect(wire.list('items'), [1, 2]);
    expect(
      wire.enumByName('kind', ThreatKind.values),
      ThreatKind.screenRecording,
    );
  });

  test('a payload that is not a map is a TransportException', () {
    expect(() => WireMap('nope'), throwsA(isA<TransportException>()));
    expect(() => WireMap(null), throwsA(isA<TransportException>()));
  });

  test('a missing or mistyped key is a TransportException', () {
    expect(() => wire.string('missing'), throwsA(isA<TransportException>()));
    expect(() => wire.integer('name'), throwsA(isA<TransportException>()));
  });

  test('an unknown enum name is a TransportException', () {
    expect(
      () => wire.enumByName('name', ThreatKind.values),
      throwsA(isA<TransportException>()),
    );
  });
}
