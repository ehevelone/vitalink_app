import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';

enum LabelSidesAction { addSide, done, cancel }

/// Shown after each document-scanner capture: the sides scanned so far and big
/// buttons to scan another side or send them all to be read.
class LabelSidesReviewScreen extends StatelessWidget {
  const LabelSidesReviewScreen({
    super.key,
    required this.imagePaths,
    this.maxSides = 4,
  });

  final List<String> imagePaths;
  final int maxSides;

  static const _navy = Color(0xFF0F172A);
  static const _vitalinkBlue = Color(0xFF78C7E7);

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final canAddSide = imagePaths.length < maxSides;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, LabelSidesAction.cancel);
      },
      child: Scaffold(
        backgroundColor: _navy,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E5A88),
          foregroundColor: Colors.white,
          title: Text(strings.sidesScanned(imagePaths.length)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: PageController(
                      initialPage: imagePaths.length - 1,
                    ),
                    itemCount: imagePaths.length,
                    itemBuilder: (_, index) => Image.file(
                      File(imagePaths[index]),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  strings.canYouReadEveryItem,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('label-sides-done'),
                  onPressed: () =>
                      Navigator.pop(context, LabelSidesAction.done),
                  icon: const Icon(Icons.check),
                  label: Text(strings.done),
                  style: FilledButton.styleFrom(
                    backgroundColor: _vitalinkBlue,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(58),
                    textStyle: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (canAddSide) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('label-sides-add'),
                    onPressed: () =>
                        Navigator.pop(context, LabelSidesAction.addSide),
                    icon: const Icon(Icons.add_a_photo),
                    label: Text(strings.addAnotherSide),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _vitalinkBlue,
                      side: const BorderSide(color: _vitalinkBlue, width: 2),
                      minimumSize: const Size.fromHeight(58),
                      textStyle: const TextStyle(fontSize: 19),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, LabelSidesAction.cancel),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(strings.cancel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
