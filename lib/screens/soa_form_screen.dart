import 'package:flutter/material.dart';
import 'package:signature/signature.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/secure_store.dart';

class SoaFormScreen extends StatefulWidget {
  const SoaFormScreen({super.key});

  @override
  State<SoaFormScreen> createState() => _SoaFormScreenState();
}

class _SoaFormScreenState extends State<SoaFormScreen> {
  final _sigController =
      SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  bool _advantage = false;
  bool _drugPlan = false;
  bool _supplement = false;
  bool _dentalVision = false;
  bool _hospitalIndemnity = false;

  String? _agentName;
  String? _agentPhone;
  String? _agentId;

  @override
  void initState() {
    super.initState();
    _loadAgent();
  }

  Future<void> _loadAgent() async {
    final store = SecureStore();
    final name = await store.getString('agentName');
    final phone = await store.getString('agentPhone');
    final id = await store.getString('agentLicense'); // using license as ID
    setState(() {
      _agentName = name;
      _agentPhone = phone;
      _agentId = id;
    });
  }

  Future<void> _savePdf() async {
    if (_sigController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Please sign before saving")),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final signature = await _sigController.toPngBytes();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Scope of Appointment Confirmation Form",
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text("Discussion Topics:"),
              pw.Bullet(
                  text:
                      "Medicare Advantage Plans: ${_advantage ? 'Yes' : 'No'}"),
              pw.Bullet(
                  text: "Prescription Drug Plan: ${_drugPlan ? 'Yes' : 'No'}"),
              pw.Bullet(
                  text: "Medicare Supplement: ${_supplement ? 'Yes' : 'No'}"),
              pw.Bullet(
                  text:
                      "Dental/Vision/Hearing: ${_dentalVision ? 'Yes' : 'No'}"),
              pw.Bullet(
                  text:
                      "Hospital Indemnity: ${_hospitalIndemnity ? 'Yes' : 'No'}"),
              pw.SizedBox(height: 20),
              pw.Text("Beneficiary Signature:"),
              if (signature != null)
                pw.Image(pw.MemoryImage(signature), width: 200, height: 80),
              pw.SizedBox(height: 40),
              pw.Text("Agent Information",
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text("Name: ${_agentName ?? ''}"),
              pw.Text("Phone: ${_agentPhone ?? ''}"),
              pw.Text("ID: ${_agentId ?? ''}"),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());

    messenger.showSnackBar(
      const SnackBar(content: Text("✅ SOA form saved as PDF")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scope of Appointment")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Select discussion topics:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              CheckboxListTile(
                value: _advantage,
                onChanged: (v) => setState(() => _advantage = v ?? false),
                title: const Text("Medicare Advantage (Part C) & Cost Plans"),
              ),
              CheckboxListTile(
                value: _drugPlan,
                onChanged: (v) => setState(() => _drugPlan = v ?? false),
                title: const Text("Standalone Prescription Drug Plan (Part D)"),
              ),
              CheckboxListTile(
                value: _supplement,
                onChanged: (v) => setState(() => _supplement = v ?? false),
                title: const Text("Medicare Supplement (Medigap) Plans"),
              ),
              CheckboxListTile(
                value: _dentalVision,
                onChanged: (v) => setState(() => _dentalVision = v ?? false),
                title: const Text("Dental / Vision / Hearing Products"),
              ),
              CheckboxListTile(
                value: _hospitalIndemnity,
                onChanged: (v) =>
                    setState(() => _hospitalIndemnity = v ?? false),
                title: const Text("Hospital Indemnity Products"),
              ),
              const SizedBox(height: 20),
              const Text("Beneficiary Signature:",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Container(
                height: 150,
                decoration:
                    BoxDecoration(border: Border.all(color: Colors.black)),
                child: Signature(
                  controller: _sigController,
                  backgroundColor: Colors.white,
                ),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () => _sigController.clear(),
                    child: const Text("Clear"),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("Save as PDF"),
                onPressed: _savePdf,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
