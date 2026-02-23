import 'dart:io';
import 'package:flutter/material.dart';

import '../models.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

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

  Future<void> _save() async {
    if (_p == null) return;
    try {
      _p!.updatedAt = DateTime.now();
      await _repo.saveProfile(_p!);
    } catch (_) {}
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
      body: ins.cards.isEmpty
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
                    path != null &&
                        path.isNotEmpty &&
                        File(path)
                            .existsSync();

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
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CardDetailViewer(
                                  card: card),
                        ),
                      );
                    },
                  ),
                );
              },
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
