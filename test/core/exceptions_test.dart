import 'package:flutter_test/flutter_test.dart';
import 'package:payment_module/core/exceptions.dart';

void main() {
  test('ServiceException carries its message and is an AppException', () {
    const e = ServiceException('no activity attached');
    expect(e.message, 'no activity attached');
    expect(e, isA<AppException>());
  });

  test('ClientException toString includes the type and message', () {
    const e = ClientException('job already running');
    expect(e.toString(), 'ClientException: job already running');
  });

  test('TransportException is distinct from ServiceException and ClientException', () {
    const e = TransportException('malformed payload');
    expect(e, isNot(isA<ServiceException>()));
    expect(e, isNot(isA<ClientException>()));
  });
}
