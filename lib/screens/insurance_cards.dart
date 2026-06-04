import 'dart:io';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';
import 'insurance_card_detail.dart';

class InsuranceCardsScreen extends StatefulWidget {
  final int index;

  const InsuranceCardsScreen(
      {super.key, required this.index});

  @override
  State<InsuranceCardsScreen> createState() =>
      _InsuranceCardsScreenState();
}

class _InsuranceCardsScreenState
    extends State<InsuranceCardsScreen> {
  late final DataRepository _repo;
  Profile? _p;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.loadProfile();

      if (!mounted) return;

      setState(() {
        _p = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  String _detectMedicarePlanId(InsuranceCard card) {
    final text = [
      card.medicarePlanId,
      card.policy,
      card.memberId,
      card.policyType,
      card.carrier,
      card.ocrText,
    ].where((value) => value.trim().isNotEmpty).join('\n').toUpperCase();

    final match = RegExp(r'\b([HSR]\d{4})[-\s]?(\d{3})(?:[-\s]?(\d{1,3}))?\b')
        .firstMatch(text);

    if (match == null) return '';

    final segment = match.group(3);
    return segment == null
        ? '${match.group(1)}-${match.group(2)}'
        : '${match.group(1)}-${match.group(2)}-${int.parse(segment)}';
  }

  void _openCard(InsuranceCard card, {bool showCopays = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InsuranceCardDetail(
          card: card,
          showCopaysOnOpen: showCopays,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
            child: CircularProgressIndicator()),
      );
    }

    if (_error ||
        _p == null ||
        widget.index >=
            _p!.insurances.length) {
      return const Scaffold(
        body: Center(
            child:
                Text("Unable to load cards")),
      );
    }

    final ins = _p!.insurances[widget.index];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          ins.carrier.isNotEmpty
              ? "${ins.carrier} – Cards"
              : "Insurance Cards",
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  // 🔥 future scan logic goes here
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.camera_alt),
                label: const Text(
                  'Scan Insurance Card',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),

          Expanded(
            child: ins.cards.isEmpty
                ? const Center(
                    child:
                        Text("No cards for this policy"))
                : ListView.builder(
                    itemCount: ins.cards.length,
                    itemBuilder:
                        (context, index) {
                      final card = ins.cards[index];

                      final path =
                          card.frontImagePath;

                      final hasImage =
                          path.isNotEmpty &&
                              File(path)
                                  .existsSync();
                      final hasMedicarePlan =
                          _detectMedicarePlanId(card).isNotEmpty;

                      return Card(
                        child: ListTile(
                          leading: hasImage
                              ? Image.file(
                                  File(path),
                                  width: 60,
                                  fit: BoxFit.cover,
                                )
                              : const Icon(
                                  Icons.credit_card,
                                  size: 40,
                                ),
                          title:
                              Text("Card ${index + 1}"),
                          subtitle:
                              Text("Source: ${card.source}"),
                          onTap: () => _openCard(card),
                          trailing: hasMedicarePlan
                              ? SizedBox(
                                  height: 34,
                                  child: FilledButton(
                                    onPressed: () => _openCard(
                                      card,
                                      showCopays: true,
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.blue.shade700,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text("Co-pays"),
                                  ),
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class CardDetailViewer extends StatefulWidget {
  final InsuranceCard card;

  const CardDetailViewer(
      {super.key, required this.card});

  @override
  State<CardDetailViewer> createState() =>
      _CardDetailViewerState();
}

class _CardDetailViewerState
    extends State<CardDetailViewer> {
  bool showingFront = true;

  @override
  Widget build(BuildContext context) {
    final front =
        widget.card.frontImagePath;
    final back =
        widget.card.backImagePath;

    final path = showingFront
        ? front
        : back;

    if (path == null ||
        path.isEmpty ||
        !File(path).existsSync()) {
      return const Scaffold(
        body: Center(
            child:
                Text("No image available")),
      );
    }

    return Scaffold(
      appBar:
          AppBar(title: const Text("Card Viewer")),
      body: GestureDetector(
        onTap: (back != null &&
                back.isNotEmpty)
            ? () => setState(
                () =>
                    showingFront =
                        !showingFront)
            : null,
        child: Center(
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
