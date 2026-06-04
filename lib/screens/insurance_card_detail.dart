import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/widgets.dart' as pw;              // ✅ ADDED
import 'package:path_provider/path_provider.dart';    // ✅ ADDED

import '../models.dart';
import '../services/api_service.dart';
import '../services/data_repository.dart';
import '../services/secure_store.dart';

class InsuranceCardDetail extends StatefulWidget {
  final InsuranceCard card;
  final VoidCallback? onDelete;
  final bool startOnBack;
  final bool showCopaysOnOpen;

  const InsuranceCardDetail({
    super.key,
    required this.card,
    this.onDelete,
    this.startOnBack = false,
    this.showCopaysOnOpen = false,
  });

  @override
  State<InsuranceCardDetail> createState() => _InsuranceCardDetailState();
}

class _InsuranceCardDetailState extends State<InsuranceCardDetail> {
  bool _showFront = true;
  final ImagePicker _picker = ImagePicker();
  late final DataRepository _repo;
  double _currentScale = 1.0;
  bool _loadingBenefits = false;

  @override
  void initState() {
    super.initState();
    _repo = DataRepository(SecureStore());
    _showFront = !widget.startOnBack;

    if (widget.showCopaysOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showCopays();
        }
      });
    }
  }

  void _toggleView() {
    if ((widget.card.backImagePath ?? '').isNotEmpty) {
      setState(() => _showFront = !_showFront);
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

  bool get _hasMedicarePlanId =>
      _detectMedicarePlanId(widget.card).isNotEmpty;

  bool get _looksLikeMedicareCard {
    final text = [
      widget.card.medicarePlanKind,
      widget.card.policyType,
      widget.card.carrier,
      widget.card.policy,
      widget.card.memberId,
      widget.card.ocrText,
    ].where((value) => value.trim().isNotEmpty).join('\n').toUpperCase();

    return text.contains('MAPD') ||
        text.contains('MA ONLY') ||
        text.contains('PDP') ||
        text.contains('MEDICARE ADVANTAGE') ||
        text.contains('PRESCRIPTION DRUG PLAN') ||
        text.contains('MEDICARE') ||
        (text.contains('HEALTH PLAN') &&
            (text.contains('AETNA') ||
                text.contains('UNITED') ||
                text.contains('HUMANA') ||
                text.contains('DEVOTED') ||
                text.contains('WELLCARE') ||
                text.contains('CIGNA') ||
                text.contains('ANTHEM') ||
                text.contains('BCBS')));
  }

  Future<void> _showCopays() async {
    final planId = _detectMedicarePlanId(widget.card);

    if (planId.isEmpty || _loadingBenefits) return;

    setState(() => _loadingBenefits = true);

    try {
      final data = await ApiService.getMedicarePlanBenefits(
        medicarePlanId: planId,
        policy: widget.card.policy,
        carrier: widget.card.carrier,
        cardText: widget.card.ocrText,
      );

      if (!mounted) return;

      if (data['success'] != true) {
        _showBenefitsError(data);
        return;
      }

      _showBenefitsDialog(data);
    } finally {
      if (mounted) {
        setState(() => _loadingBenefits = false);
      }
    }
  }

  void _showBenefitsError(Map<String, dynamic> data) {
    final message = data['error']?.toString() ??
        'Unable to load co-pays for this card.';
    final planId = data['plan_id']?.toString() ?? _detectMedicarePlanId(widget.card);
    final planYear = data['plan_year']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFF7FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Co-pays Not Found',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          [
            message,
            if (planId.isNotEmpty) 'Plan: $planId',
            if (planYear.isNotEmpty) 'Year: $planYear',
          ].join('\n\n'),
          style: const TextStyle(
            color: Color(0xFF334155),
            height: 1.35,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showBenefitsDialog(Map<String, dynamic> data) {
    final plan = Map<String, dynamic>.from(data['plan'] ?? {});
    final moop = Map<String, dynamic>.from(plan['moop'] ?? {});
    final copays = (plan['key_copays'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFFF7FAFC),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Medicare Co-pays',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (plan['plan_name'] ?? 'Medicare Plan').toString(),
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (plan['carrier_name'] ?? '').toString(),
                  style: const TextStyle(color: Color(0xFF334155)),
                ),
                if ((plan['geography'] ?? '').toString().isNotEmpty)
                  Text(
                    (plan['geography'] ?? '').toString(),
                    style: const TextStyle(color: Color(0xFF334155)),
                  ),
                const SizedBox(height: 12),
                if ((moop['in_network'] ?? '').toString().isNotEmpty)
                  _benefitRow('MOOP In-Network', moop['in_network']),
                if ((moop['combined'] ?? '').toString().isNotEmpty)
                  _benefitRow('MOOP Combined', moop['combined']),
                const Divider(height: 24),
                if (copays.isEmpty)
                  const Text(
                    'CMS found this plan, but no key co-pay rows were mapped yet.',
                    style: TextStyle(color: Color(0xFF334155)),
                  ),
                for (final copay in copays)
                  _benefitRow(
                    (copay['label'] ?? '').toString(),
                    (copay['value'] ?? '').toString(),
                  ),
                const SizedBox(height: 12),
                Text(
                  (data['message'] ?? '').toString(),
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _benefitRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value?.toString() ?? '',
              textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFF334155)),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: SEND AS PDF
  Future<void> _sendInsuranceEmail() async {
    final card = widget.card;

    final frontPath = card.frontImagePath;
    final backPath = card.backImagePath;

    if (frontPath.isEmpty && (backPath == null || backPath.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No card images available")),
      );
      return;
    }

    final pdf = pw.Document();

    final frontImage = File(frontPath).existsSync()
        ? pw.MemoryImage(File(frontPath).readAsBytesSync())
        : null;

    final backImage = (backPath != null &&
            backPath.isNotEmpty &&
            File(backPath).existsSync())
        ? pw.MemoryImage(File(backPath).readAsBytesSync())
        : null;

    if (frontImage != null) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) =>
              pw.Center(child: pw.Image(frontImage)),
        ),
      );
    }

    if (backImage != null) {
      pdf.addPage(
        pw.Page(
          build: (pw.Context context) =>
              pw.Center(child: pw.Image(backImage)),
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
        "${dir.path}/insurance_card_${DateTime.now().millisecondsSinceEpoch}.pdf");

    await file.writeAsBytes(await pdf.save());

    final subject =
        "Insurance Card – ${card.carrier.isNotEmpty ? card.carrier : "Member"}";

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: "Please find my insurance card attached for your records.",
    );
  }

  Future<void> _captureBack() async {
    try {
      final XFile? image =
          await _picker.pickImage(source: ImageSource.camera);
      if (image == null) return;

      File file = File(image.path);

      if (!mounted) return;

      setState(() {
        widget.card.backImagePath = file.path;
        _showFront = false;
      });

      final profile = await _repo.loadProfile();
      bool updated = false;

      for (var i = 0; i < profile.orphanCards.length; i++) {
        if (profile.orphanCards[i] == widget.card) {
          profile.orphanCards[i] = widget.card;
          updated = true;
          break;
        }
      }

      for (var ins in profile.insurances) {
        for (var i = 0; i < ins.cards.length; i++) {
          if (ins.cards[i] == widget.card) {
            ins.cards[i] = widget.card;
            updated = true;
            break;
          }
        }
      }

      if (updated) {
        profile.updatedAt = DateTime.now();
        await _repo.saveProfile(profile);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;

    final imagePath = _showFront
        ? card.frontImagePath
        : (card.backImagePath ?? '');

    final file = (imagePath.isNotEmpty)
        ? File(imagePath)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          card.carrier.isNotEmpty
              ? card.carrier
              : "Insurance Card",
        ),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: widget.onDelete,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: (file != null && file.existsSync())
                  ? GestureDetector(
                      onTapUp: (_) {
                        if (_currentScale == 1.0) {
                          _toggleView();
                        }
                      },
                      child: InteractiveViewer(
                        minScale: 1.0,
                        maxScale: 5.0,
                        onInteractionUpdate: (details) {
                          setState(
                              () => _currentScale = details.scale);
                        },
                        child: Image.file(
                          file,
                          fit: BoxFit.contain,
                        ),
                      ),
                    )
                  : const Icon(Icons.broken_image, size: 120),
            ),
          ),

          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  if (_hasMedicarePlanId || _looksLikeMedicareCard) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: (_loadingBenefits || !_hasMedicarePlanId)
                            ? null
                            : _showCopays,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _loadingBenefits
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.medical_information_outlined),
                        label: Text(
                          _hasMedicarePlanId
                              ? "Co-pays"
                              : "Co-pays unavailable",
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _captureBack,
                      icon: const Icon(Icons.camera_alt_outlined),
                      label: Text(
                        (card.backImagePath ?? '').isEmpty
                            ? "Add Back of Card"
                            : "Replace Back of Card",
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _sendInsuranceEmail,
                      icon: const Icon(Icons.email_outlined),
                      label: const Text("Share This Card"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
