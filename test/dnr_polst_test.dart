import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/models.dart';
import 'package:vitalink/services/profile_update_sync_service.dart';

void main() {
  test('DNR/POLST details are included in emergency profile sharing', () {
    final profile = Profile(
      fullName: 'Jordan Smith',
      emergency: EmergencyInfo(
        dnrPolstOnFile: true,
        dnrPolstLocation: 'Refrigerator door',
      ),
    );

    final payload = ProfileUpdateSyncService().buildPayload(
      profile,
      sections: const ['emergency'],
    );
    final emergency = payload['emergency'] as Map<String, dynamic>;

    expect(emergency['dnrPolstOnFile'], isTrue);
    expect(emergency['dnrPolstLocation'], 'Refrigerator door');
  });

  test('profile serialization carries DNR/POLST details for device transfer', () {
    final profile = Profile(
      fullName: 'Jordan Smith',
      emergency: EmergencyInfo(
        dnrPolstOnFile: true,
        dnrPolstLocation: 'Bedroom nightstand',
      ),
    );

    final restored = Profile.fromJson(profile.toJson());

    expect(restored.emergency.dnrPolstOnFile, isTrue);
    expect(restored.emergency.dnrPolstLocation, 'Bedroom nightstand');
  });
}
