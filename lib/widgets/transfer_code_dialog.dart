import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../services/transfer_code.dart';

/// Asks for a device-transfer code and returns it only once it has the right
/// shape, so a typo is caught before anything is sent to the server.
/// Autocorrect and suggestions are off because phone keyboards otherwise
/// "fix" random codes.
Future<String?> showTransferCodeDialog(
  BuildContext context, {
  String? title,
  String? confirmLabel,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _TransferCodeDialog(
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TransferCodeDialog extends StatefulWidget {
  const _TransferCodeDialog({this.title, this.confirmLabel});

  final String? title;
  final String? confirmLabel;

  @override
  State<_TransferCodeDialog> createState() => _TransferCodeDialogState();
}

class _TransferCodeDialogState extends State<_TransferCodeDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    try {
      TransferCode.parse(text);
      Navigator.pop(context, text);
    } on FormatException {
      setState(() => _error = AppStrings.of(context).transferCodeWrongLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? AppStrings.of(context).enterYourTransferCode),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AppStrings.of(context).transferCodeInstructions),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.visiblePassword,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              letterSpacing: 1.2,
            ),
            decoration: InputDecoration(
              labelText: AppStrings.of(context).transferCodeLabel,
              hintText: 'XXXX-XXXX-XXXXX-XXXXX',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppStrings.of(context).cancel),
        ),
        ElevatedButton(
          onPressed: _submit,
          child:
              Text(widget.confirmLabel ?? AppStrings.of(context).continueLabel),
        ),
      ],
    );
  }
}
