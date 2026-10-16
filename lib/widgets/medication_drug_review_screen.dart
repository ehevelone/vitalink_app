import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/screen_strings.dart';
import '../models.dart';
import '../services/drug_lookup_service.dart';

@visibleForTesting
double medicationLabelPhotoHeight(
  double availableHeight, {
  required bool search,
  bool keyboardOpen = false,
}) =>
    keyboardOpen ? 80 : (search ? availableHeight * .4 : 150);

class MedicationDrugReviewScreen extends StatefulWidget {
  const MedicationDrugReviewScreen({
    super.key,
    required this.medication,
    required this.lookup,
    required this.imagePaths,
    required this.current,
    required this.total,
  });

  final Medication medication;
  final DrugLookupApi lookup;
  final List<String> imagePaths;
  final int current;
  final int total;

  @override
  State<MedicationDrugReviewScreen> createState() =>
      _MedicationDrugReviewScreenState();
}

enum _ReviewStep { checking, confirm, search, strengths, unavailable }
enum _RetryAction { search, strengths }

class _MedicationDrugReviewScreenState
    extends State<MedicationDrugReviewScreen> {
  static const _navy = Color(0xFF0F172A);
  static const _header = Color(0xFF0E5A88);
  static const _vitalinkBlue = Color(0xFF78C7E7);
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;
  _ReviewStep _step = _ReviewStep.checking;
  DrugProduct? _match;
  List<String> _names = const [];
  List<DrugProduct> _products = const [];
  bool _loading = false;
  bool _searchCameFromConfirm = false;
  bool _networkError = false;
  _RetryAction? _retryAction;
  String _selectedName = '';

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _verify();
  }

  void _onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode
      ..removeListener(_onSearchFocusChanged)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final result = await widget.lookup.verify(
      name: widget.medication.name,
      dose: widget.medication.dose,
      form: widget.medication.drugForm,
      ndc: widget.medication.ndc,
    );
    if (!mounted) return;
    setState(() {
      if (result.isSure) {
        _match = result.match;
        _step = _ReviewStep.confirm;
      } else if (result.isUnavailable) {
        _step = _ReviewStep.unavailable;
      } else {
        _searchCameFromConfirm = false;
        _step = _ReviewStep.search;
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _names = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      await _runSearch(query);
    });
  }

  Future<void> _runSearch(String query) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _networkError = false;
      });
    }
    final result = await widget.lookup.search(query);
    if (!mounted || _searchController.text.trim() != query) return;
    setState(() {
      _loading = false;
      if (result.available) {
        _names = result.names;
      } else {
        _names = const [];
        _networkError = true;
        _retryAction = _RetryAction.search;
      }
    });
  }

  Future<void> _chooseName(String name) async {
    _selectedName = name;
    await _loadStrengths(name);
  }

  Future<void> _loadStrengths(String name) async {
    setState(() {
      _loading = true;
      _names = const [];
      _networkError = false;
    });
    final result = await widget.lookup.strengths(name);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (!result.available) {
        _networkError = true;
        _retryAction = _RetryAction.strengths;
      } else {
        _products = result.products;
        _step = _ReviewStep.strengths;
      }
    });
  }

  Future<void> _chooseProduct(DrugProduct product) async {
    setState(() => _loading = true);
    final result = await widget.lookup.select(product.rxcui);
    if (!mounted) return;
    if (result.isSure) {
      Navigator.pop(context, _confirmed(result.match!));
      return;
    }
    setState(() {
      _loading = false;
      _step = result.isUnavailable
          ? _ReviewStep.unavailable
          : _ReviewStep.search;
    });
  }

  Medication _confirmed(DrugProduct product) {
    final parts = _splitFriendlyName(product.friendlyName);
    return widget.medication.copyWith(
      name: parts.$1,
      dose: parts.$2,
      rxcui: product.rxcui,
      ndc: product.ndc.isEmpty ? widget.medication.ndc : product.ndc,
      ndcSource:
          product.ndcSource.isEmpty ? widget.medication.ndcSource : product.ndcSource,
      drugForm: product.form,
      drugType: product.drugType,
      matchStatus: 'confirmed',
      updatedAt: DateTime.now(),
    );
  }

  Medication _unmatched() => widget.medication.copyWith(
        matchStatus: 'unmatched',
        updatedAt: DateTime.now(),
      );

  Future<void> _handleBack() async {
    if (_step == _ReviewStep.strengths) {
      setState(() {
        _networkError = false;
        _step = _ReviewStep.search;
      });
      return;
    }
    if (_step == _ReviewStep.search && _searchCameFromConfirm) {
      setState(() {
        _networkError = false;
        _step = _ReviewStep.confirm;
      });
      return;
    }
    final skip = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.of(context).stopCheckingMedicine),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppStrings.of(context).keepChecking),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppStrings.of(context).skipIt),
          ),
        ],
      ),
    );
    if (skip == true && mounted) Navigator.pop(context, _unmatched());
  }

  void _searchAgain() {
    setState(() {
      _networkError = false;
      _products = const [];
      _step = _ReviewStep.search;
    });
  }

  void _retry() {
    if (_retryAction == _RetryAction.strengths) {
      _loadStrengths(_selectedName);
    } else {
      _runSearch(_searchController.text.trim());
    }
  }

  String _normalCase(String value) {
    final lower = value.toLowerCase();
    return lower.replaceAllMapped(
      RegExp(r'(^|[\s/()-])([a-z])'),
      (match) => '${match.group(1)}${match.group(2)!.toUpperCase()}',
    );
  }

  (String, String) _splitFriendlyName(String value) {
    final match = RegExp(
      r'^(.*?)(\s+(?:ER\s+|DR\s+)?\d+(?:\.\d+)?\s+(?:mcg|mg|g|mEq|units)(?:/[^ ]+)?\b.*)$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return (value, widget.medication.dose);
    return (match.group(1)!.trim(), match.group(2)!.trim());
  }

  void _showPhoto(String path) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.file(File(path), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _photos(double availableHeight, {required bool keyboardOpen}) {
    if (widget.imagePaths.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('label-photo-panel'),
      height: medicationLabelPhotoHeight(
        availableHeight,
        search: _step == _ReviewStep.search,
        keyboardOpen: keyboardOpen,
      ),
      child: PageView.builder(
        itemCount: widget.imagePaths.length,
        itemBuilder: (_, index) => Semantics(
          button: true,
          label: 'Medication label ${index + 1}',
          child: InkWell(
            onTap: () => _showPhoto(widget.imagePaths[index]),
            child: Image.file(File(widget.imagePaths[index]), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0 ||
        (_step == _ReviewStep.search && _searchFocusNode.hasFocus);
    final showBottomSkip =
        _step == _ReviewStep.confirm || _step == _ReviewStep.strengths;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: _navy,
        appBar: AppBar(
          backgroundColor: _header,
          foregroundColor: Colors.white,
          title: Text(strings.medicineProgress(widget.current, widget.total)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_step != _ReviewStep.search) ...[
                    _photos(
                      constraints.maxHeight,
                      keyboardOpen: keyboardOpen,
                    ),
                    if (widget.imagePaths.isNotEmpty)
                      const SizedBox(height: 20),
                  ],
                  Expanded(
                    child: _body(
                      strings,
                      keyboardOpen: keyboardOpen,
                      availableHeight: constraints.maxHeight,
                    ),
                  ),
                  if (showBottomSkip) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(context, _unmatched()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _vitalinkBlue,
                        side: const BorderSide(color: _vitalinkBlue),
                        minimumSize: const Size.fromHeight(54),
                      ),
                      child: Text(strings.skipForNow),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    AppStrings strings, {
    required bool keyboardOpen,
    required double availableHeight,
  }) {
    if (_step == _ReviewStep.checking) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(strings.checkingMedicine,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: Colors.white)),
          ],
        ),
      );
    }
    if (_step == _ReviewStep.unavailable) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 52, color: _vitalinkBlue),
            const SizedBox(height: 20),
            Text(
              strings.medicineCheckUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: () => Navigator.pop(context, _unmatched()),
              style: FilledButton.styleFrom(
                backgroundColor: _vitalinkBlue,
                foregroundColor: _navy,
                minimumSize: const Size.fromHeight(54),
              ),
              child: Text(strings.continueLabel),
            ),
          ],
        ),
      );
    }
    if (_step == _ReviewStep.confirm) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.isThisYourMedicine,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white)),
          const SizedBox(height: 20),
          Text(
            _match!.friendlyName,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: _vitalinkBlue, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 36),
          FilledButton(
            onPressed: () => Navigator.pop(context, _confirmed(_match!)),
            style: FilledButton.styleFrom(
              backgroundColor: _vitalinkBlue,
              foregroundColor: _navy,
              minimumSize: const Size.fromHeight(56),
            ),
            child: Text(strings.medicineYes),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => setState(() {
              _searchController.clear();
              _names = const [];
              _searchCameFromConfirm = true;
              _step = _ReviewStep.search;
            }),
            style: OutlinedButton.styleFrom(
              foregroundColor: _vitalinkBlue,
              side: const BorderSide(color: _vitalinkBlue),
              minimumSize: const Size.fromHeight(56),
            ),
            child: Text(strings.medicineNo),
          ),
        ],
      );
    }
    if (_step == _ReviewStep.strengths) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.chooseStrength,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: Colors.white)),
          const SizedBox(height: 16),
          Expanded(
            child: _networkError
                ? _networkErrorBody(strings)
                : _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? Center(
                        child: Text(
                          strings.noStrengthsFound,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: Colors.white),
                        ),
                      )
                : ListView.separated(
                    itemCount: _products.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) => ListTile(
                      minTileHeight: 58,
                      title: Text(_products[index].friendlyName,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18)),
                      trailing: const Icon(Icons.chevron_right,
                          color: _vitalinkBlue),
                      onTap: () => _chooseProduct(_products[index]),
                    ),
                  ),
          ),
          FilledButton.tonal(
            onPressed: _searchAgain,
            style: FilledButton.styleFrom(
              backgroundColor: _vitalinkBlue,
              foregroundColor: _navy,
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(strings.searchAgain),
          ),
        ],
      );
    }
    return ListView(
      key: const Key('drug-search-scroll'),
      children: [
        _photos(availableHeight, keyboardOpen: keyboardOpen),
        if (widget.imagePaths.isNotEmpty) const SizedBox(height: 20),
        Text(strings.medicineNameUnclear,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: Colors.white)),
        const SizedBox(height: 18),
        TextField(
          key: const Key('drug-search-field'),
          controller: _searchController,
          focusNode: _searchFocusNode,
          autofocus: true,
          onChanged: _onSearchChanged,
          style: const TextStyle(color: Colors.white, fontSize: 20),
          decoration: InputDecoration(
            labelText: strings.searchMedicineName,
            labelStyle: const TextStyle(color: Colors.white70),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _vitalinkBlue, width: 2),
            ),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 12),
        if (_networkError)
          _networkErrorBody(strings)
        else if (_names.isEmpty &&
            _searchController.text.length >= 2 &&
            !_loading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              strings.noMedicineMatches,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          )
        else
          for (var index = 0; index < _names.length; index++) ...[
            if (index > 0) const Divider(),
            ListTile(
              minTileHeight: 58,
              title: Text(
                _normalCase(_names[index]),
                style: const TextStyle(color: Colors.white, fontSize: 19),
              ),
              trailing:
                  const Icon(Icons.chevron_right, color: _vitalinkBlue),
              onTap: () => _chooseName(_names[index]),
            ),
          ],
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('keyboard-skip-medicine'),
          onPressed: () => Navigator.pop(context, _unmatched()),
          style: OutlinedButton.styleFrom(
            foregroundColor: _vitalinkBlue,
            side: const BorderSide(color: _vitalinkBlue),
            minimumSize: const Size.fromHeight(54),
          ),
          child: Text(strings.skipForNow),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _networkErrorBody(AppStrings strings) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.medicineListUnavailable,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _retry,
              style: FilledButton.styleFrom(
                backgroundColor: _vitalinkBlue,
                foregroundColor: _navy,
              ),
              child: Text(strings.tryAgain),
            ),
          ],
        ),
      );
}
