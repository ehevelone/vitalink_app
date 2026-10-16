import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/screens/meds_screen.dart';

void main() {
  test('retail chains are local without asking', () {
    expect(knownPharmacyType('Walmart Pharmacy'), 'retail');
    expect(knownPharmacyType('WALGREENS #1234\n402-555-1111'), 'retail');
    expect(knownPharmacyType('CVS Pharmacy'), 'retail');
    expect(knownPharmacyType('Hy-Vee Pharmacy'), 'retail');
  });

  test('mail-order names are mail order, checked before retail chains', () {
    expect(knownPharmacyType('CVS Caremark'), 'mail_order');
    expect(knownPharmacyType('Express Scripts Pharmacy'), 'mail_order');
    expect(knownPharmacyType('CenterWell Pharmacy'), 'mail_order');
    expect(knownPharmacyType('Amazon Pharmacy'), 'mail_order');
    expect(knownPharmacyType('AllianceRx Walgreens Pharmacy'), 'mail_order');
    expect(knownPharmacyType('Walgreens Mail Service'), 'mail_order');
  });

  test('a street address on the bottle means a local store', () {
    expect(
      knownPharmacyType('Main Street Drug\n123 Main St\nOmaha, NE 68104'),
      'retail',
    );
  });

  test('a bottle from another state asks, even for a retail chain', () {
    const outOfState = 'Walgreens\n1000 Commerce Dr\nOrlando, FL 32801';
    expect(knownPharmacyType(outOfState, clientState: 'NE'), isNull);
    expect(knownPharmacyType(outOfState, clientState: 'Nebraska'), isNull);
    expect(knownPharmacyType(outOfState, clientState: 'FL'), 'retail');
    const inState = 'Walgreens\n240 S 77th St\nOmaha, NE 68114';
    expect(knownPharmacyType(inState, clientState: 'Nebraska'), 'retail');
    // Without a bottle address or client state, the chain rule still applies.
    expect(knownPharmacyType('Walgreens', clientState: 'NE'), 'retail');
    expect(knownPharmacyType(outOfState), 'retail');
  });

  test('unknown names without an address still ask the client', () {
    expect(knownPharmacyType('Smithfield Rx\n402-555-1111'), isNull);
    expect(knownPharmacyType(''), isNull);
    expect(knownPharmacyType('Targeted Care Pharmacy'), isNull);
  });
}
