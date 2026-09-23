import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/services/deep_link_service.dart';

void main() {
  test('RSM QR opens agent terms with its generated agent code', () {
    final link = VitaLinkRegistrationLink.fromUri(
      Uri.parse('vitalink://activate?code=AGT-NEWAGENT&kind=agent'),
    );
    expect(link?.code, 'AGT-NEWAGENT');
    expect(link?.route, '/terms_agent');
  });

  test('older agent onboarding link remains an agent registration link', () {
    final link = VitaLinkRegistrationLink.fromUri(
      Uri.parse('vitalink://register?code=AGT-OLD'),
    );
    expect(link?.route, '/terms_agent');
  });

  test('agent QR opens client terms with the agent unlock code', () {
    final link = VitaLinkRegistrationLink.fromUri(
      Uri.parse('vitalink://activate?code=AGT-CLIENTS&kind=user'),
    );
    expect(link?.code, 'AGT-CLIENTS');
    expect(link?.route, '/terms_user');
  });

  test('paid consumer activation stays on the user registration path', () {
    final link = VitaLinkRegistrationLink.fromUri(
      Uri.parse('vitalink://activate?code=VL-PAID'),
    );
    expect(link?.route, '/terms_user');
  });

  test('legacy path activation link preserves its code', () {
    final link = VitaLinkRegistrationLink.fromUri(
      Uri.parse('vitalink://activate/AGT-OLD'),
    );
    expect(link?.code, 'AGT-OLD');
  });

  test('profile sharing is never sent through registration', () {
    expect(
      VitaLinkRegistrationLink.fromUri(
        Uri.parse('vitalink://share?code=FAMILY-INVITE'),
      ),
      isNull,
    );
  });

  test('emergency and recovery links do not open registration', () {
    expect(
      VitaLinkRegistrationLink.fromUri(
        Uri.parse('vitalink://emergency?code=EMERGENCY-1'),
      ),
      isNull,
    );
    expect(
      VitaLinkRegistrationLink.fromUri(
        Uri.parse('vitalink://recover?code=RESET-1'),
      ),
      isNull,
    );
  });

  test('missing or malformed registration codes do not navigate', () {
    expect(VitaLinkRegistrationLink.fromUri(Uri.parse('vitalink://activate')), isNull);
    expect(
      VitaLinkRegistrationLink.fromUri(
        Uri.parse('vitalink://activate?code=bad%20code&kind=agent'),
      ),
      isNull,
    );
  });
}
