import 'package:flutter/material.dart';
import '../l10n/screen_strings.dart';
import '../l10n/app_strings.dart';
import 'package:flutter/services.dart';

import '../services/npi_verification_service.dart';

const List<String> npiDoctorSpecialtyOptions = [
  'Primary',
  'Cardiologist',
  'Orthopedic',
  'Neurologist',
  'Endocrinologist',
  'Pulmonologist',
  'Gastroenterologist',
  'Nephrologist',
  'Urologist',
  'Oncologist',
  'Dermatologist',
  'Psychiatrist',
  'Psychologist / Clinical Psychologist',
  'Clinical Social Worker',
  'Professional Counselor',
  'Mental Health Counselor',
  'Marriage & Family Therapist',
  'Psychiatric Nurse Practitioner',
  'Addiction Counselor',
  'Pain Management',
  'Other',
];

class NpiSpecialtySelection {
  final String filterLabel;
  final String displayValue;

  const NpiSpecialtySelection({
    required this.filterLabel,
    required this.displayValue,
  });
}

Future<String?> showDoctorZipPrompt({
  required BuildContext context,
  required String doctorName,
  String? registeredZip,
  bool refiningSearch = false,
}) async {
  final formKey = GlobalKey<FormState>();
  final homeZip = registeredZip?.trim() ?? '';
  var zipValue = '';

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppStrings.of(context).whereIsThisDoctor),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              refiningSearch
                  ? AppStrings.of(context).enterZipToNarrow(doctorName)
                  : homeZip.isEmpty
                      ? AppStrings.of(context).enterZipFor(doctorName)
                      : AppStrings.of(context)
                          .couldNotFindInRegisteredZip(doctorName, homeZip),
            ),
            const SizedBox(height: 16),
            TextFormField(
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.search,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(5),
              ],
              decoration: InputDecoration(
                labelText: AppStrings.of(context).doctorZipCode,
                hintText: '12345',
              ),
              validator: (value) => RegExp(r'^\d{5}$').hasMatch(value ?? '')
                  ? null
                  : AppStrings.of(context).enterFiveDigitZip,
              onChanged: (value) => zipValue = value,
              onFieldSubmitted: (value) {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogContext, value);
                }
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppStrings.of(context).leaveUnresolved),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              Navigator.pop(dialogContext, zipValue);
            }
          },
          child: Text(AppStrings.of(context).searchZip),
        ),
      ],
    ),
  );
  return result;
}

Future<String?> showPharmacyZipPrompt({required BuildContext context}) async {
  final formKey = GlobalKey<FormState>();
  var zipValue = '';

  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppStrings.of(context).pharmacyZipCode),
      content: Form(
        key: formKey,
        child: TextFormField(
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.search,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: InputDecoration(
            labelText: AppStrings.of(context).zipCode,
            hintText: '12345',
          ),
          validator: (value) => RegExp(r'^\d{5}$').hasMatch(value ?? '')
              ? null
              : AppStrings.of(context).enterFiveDigitZipSentence,
          onChanged: (value) => zipValue = value,
          onFieldSubmitted: (value) {
            if (formKey.currentState?.validate() == true) {
              Navigator.pop(dialogContext, value);
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppStrings.of(context).cancel),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              Navigator.pop(dialogContext, zipValue);
            }
          },
          child: Text(AppStrings.of(context).search),
        ),
      ],
    ),
  );
}

Future<NpiSpecialtySelection?> showNpiSpecialtyPicker({
  required BuildContext context,
  required String doctorName,
  String? initialValue,
}) async {
  final normalizedInitial = initialValue?.trim() ?? '';
  String selected = npiDoctorSpecialtyOptions.contains(normalizedInitial)
      ? normalizedInitial
      : normalizedInitial.isNotEmpty
          ? 'Other'
          : npiDoctorSpecialtyOptions.first;
  final otherController = TextEditingController(
    text: selected == 'Other' ? normalizedInitial : '',
  );

  final result = await showDialog<NpiSpecialtySelection>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(AppStrings.of(context).whatTypeOfDoctor),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doctorName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.of(context).narrowNpiMatches,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration:
                  InputDecoration(labelText: AppStrings.of(context).doctorType),
              items: npiDoctorSpecialtyOptions
                  .map(
                    (option) => DropdownMenuItem(
                      value: option,
                      child: Text(
                        AppStrings.of(context).doctorSpecialtyLabel(option),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setDialogState(() => selected = value);
              },
            ),
            if (selected == 'Other') ...[
              const SizedBox(height: 12),
              TextField(
                controller: otherController,
                decoration: InputDecoration(
                  labelText: AppStrings.of(context).doctorTypeOptional,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppStrings.of(context).leaveUnresolved),
          ),
          FilledButton(
            onPressed: () {
              final displayValue =
                  selected == 'Other' ? otherController.text.trim() : selected;
              Navigator.pop(
                dialogContext,
                NpiSpecialtySelection(
                  filterLabel: selected,
                  displayValue: displayValue.isEmpty ? selected : displayValue,
                ),
              );
            },
            child: Text(AppStrings.of(context).narrowMatches),
          ),
        ],
      ),
    ),
  );
  otherController.dispose();
  return result;
}

// Builder supplies a context so the hover labels follow the app language.
Widget npiStatusIcon(String status) => Builder(
      builder: (context) => _npiStatusIcon(context, status),
    );

Widget _npiStatusIcon(BuildContext context, String status) {
  if (status == 'va_verified') {
    return Tooltip(
      message: AppStrings.of(context).vaProviderVerified,
      child: const Icon(Icons.military_tech, color: Colors.blue, size: 19),
    );
  }
  if (status == 'verified') {
    return Tooltip(
      message: AppStrings.of(context).npiVerified,
      child: const Icon(Icons.check_circle, color: Colors.green, size: 18),
    );
  }
  return Tooltip(
    message: status == 'needs_review'
        ? AppStrings.of(context).npiMatchNeedsReview
        : AppStrings.of(context).npiNotVerified,
    child: Icon(
      status == 'needs_review' ? Icons.flag_outlined : Icons.warning_amber,
      color: status == 'needs_review' ? Colors.orange : Colors.amber.shade800,
      size: 18,
    ),
  );
}

Widget primaryCareIndicator() {
  return Builder(
    builder: (context) => Tooltip(
      message: AppStrings.of(context).primaryCareProvider,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.health_and_safety_outlined, size: 17),
          const SizedBox(width: 4),
          Text(
            AppStrings.of(context).primaryCare,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> showNpiCandidatePicker({
  required BuildContext context,
  required String title,
  required List<Map<String, dynamic>> candidates,
  bool allowAlternateZip = false,
  int candidateLimit = 4,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                candidates.isEmpty
                    ? allowAlternateZip
                        ? AppStrings.of(context).noMatchingRecordsTryPharmacyZip
                        : AppStrings.of(context).noMatchingRecords
                    : AppStrings.of(context).chooseMatchingRecord,
              ),
              const SizedBox(height: 12),
              ...candidates.take(candidateLimit).map((candidate) {
                final address = [
                  candidate['address1'],
                  candidate['address2'],
                  [
                    candidate['city'],
                    candidate['state'],
                    formatRegistryPostalCode(
                      candidate['postalCode'],
                    ),
                  ]
                      .where(
                        (value) =>
                            value != null && value.toString().trim().isNotEmpty,
                      )
                      .join(' '),
                ]
                    .where(
                      (value) =>
                          value != null && value.toString().trim().isNotEmpty,
                    )
                    .join('\n');
                final details = [candidate['taxonomy'], candidate['credential']]
                    .where(
                      (value) =>
                          value != null && value.toString().trim().isNotEmpty,
                    )
                    .join(' • ');
                final distance = candidate['distanceMiles'] is num
                    ? (candidate['distanceMiles'] as num).toDouble()
                    : null;
                final isVaProvider = candidate['isVaProvider'] == true;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.all(14),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => Navigator.pop(dialogContext, candidate),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                (candidate['displayName'] ??
                                        AppStrings.of(context).provider)
                                    .toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (candidate['suggested'] == true)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  AppStrings.of(context).previouslyConfirmed,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            if (isVaProvider)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  AppStrings.of(context).vaProvider,
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(details),
                        ],
                        if (distance != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            distance < 0.1
                                ? AppStrings.of(context).inYourZipCode
                                : AppStrings.of(context).aboutMilesAway(
                                    distance.toStringAsFixed(1)),
                          ),
                        ],
                        if (address.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(address),
                        ],
                        if (isVaProvider &&
                            candidate['vaFacility']
                                    ?.toString()
                                    .trim()
                                    .isNotEmpty ==
                                true) ...[
                          const SizedBox(height: 4),
                          Text(candidate['vaFacility'].toString()),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        if (allowAlternateZip)
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              const <String, dynamic>{'_pickerAction': 'searchAnotherZip'},
            ),
            child: Text(AppStrings.of(context).searchAnotherZip),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(AppStrings.of(context).leaveUnresolved),
        ),
      ],
    ),
  );
}
