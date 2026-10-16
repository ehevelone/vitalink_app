import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/main.dart';
import 'package:vitalink/services/deep_link_service.dart';

void main() {
  setUp(() {
    resetIncomingUriDeduplication();
    VitaLinkDeepLink.clear();
    VitaLinkDeepLink.clearShareCode();
    VitaLinkDeepLink.clearOnboardingCode();
  });

  test('incoming URI parses activation, share, and onboarding codes', () {
    final navigations = <String>[];
    final capturedArguments = <Object?>[];

    void captureNavigation(String route, {Object? arguments}) {
      navigations.add(route);
      capturedArguments.add(arguments);
    }

    expect(
      handleIncomingUri(
        Uri.parse('vitalink://activate?code=agent123'),
        handledAt: DateTime(2026, 1, 1),
        navigate: captureNavigation,
      ),
      isTrue,
    );
    expect(VitaLinkDeepLink.code, 'AGENT123');

    expect(
      handleIncomingUri(
        Uri.parse('vitalink://share?code=ABC123.aB-c_9XyZ'),
        handledAt: DateTime(2026, 1, 1, 0, 0, 4),
        navigate: captureNavigation,
      ),
      isTrue,
    );
    expect(VitaLinkDeepLink.shareCode, 'ABC123.aB-c_9XyZ');
    expect(navigations.last, '/profile_accept');

    expect(
      handleIncomingUri(
        Uri.parse('vitalink://activate?onboarding=office789'),
        handledAt: DateTime(2026, 1, 1, 0, 0, 8),
        navigate: captureNavigation,
      ),
      isTrue,
    );
    expect(VitaLinkDeepLink.onboardingCode, 'OFFICE789');
    expect(navigations.last, '/terms_user');
    expect(capturedArguments.last, {'onboard': 'OFFICE789'});
  });

  test('identical URI is ignored for three seconds', () {
    final uri = Uri.parse('vitalink://activate?code=ABC123');
    final firstHandledAt = DateTime(2026, 1, 1);

    expect(handleIncomingUri(uri, handledAt: firstHandledAt), isTrue);
    expect(
      handleIncomingUri(
        uri,
        handledAt: firstHandledAt.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
    expect(
      handleIncomingUri(
        uri,
        handledAt: firstHandledAt.add(const Duration(seconds: 3)),
      ),
      isTrue,
    );
  });

  test('initial-link fallback ignores URI already handled by stream', () {
    final uri = Uri.parse('vitalink://share?code=ABC123.aB-c_9XyZ');
    final firstHandledAt = DateTime(2026, 1, 1);
    void ignoreNavigation(String route, {Object? arguments}) {}

    expect(
      handleIncomingUri(
        uri,
        handledAt: firstHandledAt,
        navigate: ignoreNavigation,
      ),
      isTrue,
    );
    expect(
      handleIncomingUri(
        uri,
        handledAt: firstHandledAt.add(const Duration(seconds: 10)),
        isInitialLinkFallback: true,
      ),
      isFalse,
    );
    expect(VitaLinkDeepLink.shareCode, 'ABC123.aB-c_9XyZ');
  });
}
