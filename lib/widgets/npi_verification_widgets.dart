import 'package:flutter/material.dart';
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
}) async {
  final formKey = GlobalKey<FormState>();
  final homeZip = registeredZip?.trim() ?? '';
  var zipValue = '';

  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Where is this doctor?'),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              homeZip.isEmpty
                  ? 'Enter the ZIP code for $doctorName.'
                  : 'We couldn\'t find $doctorName in your registered ZIP ($homeZip). Enter the ZIP code where the doctor is located.',
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
              decoration: const InputDecoration(
                labelText: 'Doctor ZIP code',
                hintText: '12345',
              ),
              validator: (value) => RegExp(r'^\d{5}$').hasMatch(value ?? '')
                  ? null
                  : 'Enter a 5-digit ZIP code',
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
          child: const Text('Leave unresolved'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              Navigator.pop(dialogContext, zipValue);
            }
          },
          child: const Text('Search ZIP'),
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
      title: const Text('Pharmacy ZIP code'),
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
          decoration: const InputDecoration(
            labelText: 'ZIP code',
            hintText: '12345',
          ),
          validator: (value) => RegExp(r'^\d{5}$').hasMatch(value ?? '')
              ? null
              : 'Enter a five-digit ZIP code.',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              Navigator.pop(dialogContext, zipValue);
            }
          },
          child: const Text('Search'),
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
        title: const Text('What type of doctor is this?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              doctorName,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            const Text(
              'This can narrow the NPI matches before you choose a provider.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selected,
              decoration: const InputDecoration(labelText: 'Doctor type'),
              items: npiDoctorSpecialtyOptions
                  .map(
                    (option) =>
                        DropdownMenuItem(value: option, child: Text(option)),
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
                decoration: const InputDecoration(
                  labelText: 'Doctor type (optional)',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Leave unresolved'),
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
            child: const Text('Narrow matches'),
          ),
        ],
      ),
    ),
  );
  otherController.dispose();
  return result;
}

Widget npiStatusIcon(String status) {
  if (status == 'va_verified') {
    return const Tooltip(
      message: 'VA provider verified',
      child: Icon(Icons.military_tech, color: Colors.blue, size: 19),
    );
  }
  if (status == 'verified') {
    return const Tooltip(
      message: 'NPI verified',
      child: Icon(Icons.check_circle, color: Colors.green, size: 18),
    );
  }
  return Tooltip(
    message: status == 'needs_review'
        ? 'NPI match needs review'
        : 'NPI not verified',
    child: Icon(
      status == 'needs_review' ? Icons.flag_outlined : Icons.warning_amber,
      color: status == 'needs_review' ? Colors.orange : Colors.amber.shade800,
      size: 18,
    ),
  );
}

Widget primaryCareIndicator() {
  return const Tooltip(
    message: 'Primary care provider',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.health_and_safety_outlined, size: 17),
        SizedBox(width: 4),
        Text(
          'Primary Care',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
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
                        ? 'No matching records here. Try the pharmacy ZIP, or leave it unresolved.'
                        : 'No matching records found. Leave it unresolved if none match.'
                    : 'Choose the matching record, or leave it unresolved.',
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
                                (candidate['displayName'] ?? 'Provider')
                                    .toString(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (candidate['suggested'] == true)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Text(
                                  'Previously confirmed',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            if (isVaProvider)
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Text(
                                  'VA Provider',
                                  style: TextStyle(
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
            child: const Text('Search another ZIP'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Leave unresolved'),
        ),
      ],
    ),
  );
}
