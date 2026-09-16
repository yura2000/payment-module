import '../../../../core/money.dart';
import '../domain/payment.dart';
import '../domain/payment_repository.dart';

const _demoPayment = Payment(
  reference: 'PAY-DEMO-0001',
  amount: Money(amountMinor: 4200, currency: 'USD'),
  payee: 'Acme Utilities',
  lineItems: [
    LineItem(
      description: 'Monthly service',
      amount: Money(amountMinor: 3200, currency: 'USD'),
    ),
    LineItem(
      description: 'Usage overage',
      amount: Money(amountMinor: 1000, currency: 'USD'),
    ),
  ],
);

/// The demo backend: a single, fixed Payment. Stands in for the real backend a product would
/// have — see docs/architecture.md §2 principle 2. No failure mode: an in-memory constant cannot
/// fail to load.
class InMemoryPaymentRepository implements PaymentRepository {
  @override
  Future<Payment> load() async => _demoPayment;
}
