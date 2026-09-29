import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/screens/profile_user_screen.dart';

void main() {
  test('My Profile prefers active registration demographics', () {
    expect(
      profileValueOrFallback('Registration Name', 'Legacy Name'),
      'Registration Name',
    );
    expect(profileValueOrFallback('68114', '00000'), '68114');
  });

  test('My Profile falls back for legacy users with blank profile values', () {
    expect(profileValueOrFallback('', 'Legacy Name'), 'Legacy Name');
    expect(profileValueOrFallback(null, '68114'), '68114');
  });
}
