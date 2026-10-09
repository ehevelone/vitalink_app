import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vitalink/l10n/app_strings.dart';
import 'package:vitalink/l10n/screen_strings.dart';
import 'package:vitalink/l10n/server_messages.dart';
import 'package:vitalink/legal/user_agreement_text.dart';
import 'package:vitalink/services/language_service.dart';

void main() {
  test('server messages are shown in Spanish for Spanish users', () {
    expect(
      localizeServerMessage('That access code is not valid', 'es'),
      'Ese código de acceso no es válido',
    );
    expect(
      localizeServerMessage('Server returned 400', 'es'),
      'El servidor respondió con el código 400',
    );
    expect(
      localizeServerMessage('That access code is not valid', 'en'),
      'That access code is not valid',
    );
  });

  test('status codes the app checks are never translated', () {
    for (final code in [
      'Unauthorized',
      'DEVICE_ACTIVE',
      'DEVICE_REVOKED',
      'INSTALLATION_RECOVERY_NOT_VERIFIED',
      'TRANSFER_CODE_INVALID',
      'TRANSFER_REQUIRED',
    ]) {
      expect(localizeServerMessage(code, 'es'), code);
    }
  });

  test('services without a screen follow the chosen app language', () {
    LanguageService.localeNotifier.value = const Locale('es');
    expect(AppStrings.current().languageCode, 'es');
    expect(AppStrings.current().unableToCreateTransfer,
        'No se pudo crear el traslado.');
    LanguageService.localeNotifier.value = const Locale('en');
    expect(AppStrings.current().unableToCreateTransfer,
        'Unable to create transfer.');
    LanguageService.localeNotifier.value = null;
  });

  test('stored English values get Spanish labels without changing the value',
      () {
    const es = AppStrings('es');
    expect(es.relationshipLabel('Friend'), 'Amigo');
    expect(es.referralStatusLabel('Agent Contacted'), 'Agente se comunicó');
    expect(es.prospectTopicLabel('Life Insurance'), 'seguro de vida');
    expect(const AppStrings('en').relationshipLabel('Friend'), 'Friend');
  });

  test('the user agreement is shown in the app language', () {
    expect(userAgreementTextFor('es'), startsWith('ACUERDO DE USUARIO'));
    expect(userAgreementTextFor('en'), startsWith('VITALINK USER AGREEMENT'));
  });
}
