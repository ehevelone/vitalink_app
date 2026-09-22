import 'package:flutter/material.dart';

Widget npiStatusIcon(String status) {
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

Future<Map<String, dynamic>?> showNpiCandidatePicker({
  required BuildContext context,
  required String title,
  required List<Map<String, dynamic>> candidates,
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
              const Text('Choose the matching record, or leave it unresolved.'),
              const SizedBox(height: 12),
              ...candidates.take(4).map((candidate) {
                final address = [
                  candidate['address1'],
                  candidate['address2'],
                  [
                    candidate['city'],
                    candidate['state'],
                    candidate['postalCode']
                  ]
                      .where((value) =>
                          value != null && value.toString().trim().isNotEmpty)
                      .join(' '),
                ]
                    .where((value) =>
                        value != null && value.toString().trim().isNotEmpty)
                    .join('\n');
                final details = [
                  candidate['taxonomy'],
                  candidate['credential'],
                ]
                    .where((value) =>
                        value != null && value.toString().trim().isNotEmpty)
                    .join(' • ');

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
                                    fontWeight: FontWeight.w700),
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
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Leave unresolved'),
        ),
      ],
    ),
  );
}
