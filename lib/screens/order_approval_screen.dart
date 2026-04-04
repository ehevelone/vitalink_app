import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OrderApprovalScreen extends StatefulWidget {
  final int? requestId;

  const OrderApprovalScreen({super.key, this.requestId});

  @override
  State<OrderApprovalScreen> createState() => _OrderApprovalScreenState();
}

class _OrderApprovalScreenState extends State<OrderApprovalScreen> {

  bool loading = true;
  List orders = [];

  int? requestId;
  bool _loadedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_loadedOnce) return;
    _loadedOnce = true;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args is Map && args["request_id"] != null) {
      requestId = int.tryParse(args["request_id"].toString());
    } else {
      requestId = widget.requestId;
    }

    loadOrders();
  }

  Future<void> loadOrders() async {
    try {
      final res = await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/get_pending_orders"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "request_id": requestId
        })
      );

      final data = jsonDecode(res.body);

      if (data["success"] == true) {
        setState(() {
          orders = data["orders"];
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }

    } catch (e) {
      setState(() => loading = false);
    }
  }

  Future<void> approveOrder(int orderId) async {

    print("APPROVE CLICKED: $orderId");

    try {
      final res = await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/approve-order-request"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "order_id": orderId
        })
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["success"] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order approved"))
          );
        }

        await loadOrders();

        if (mounted) {
          Navigator.pop(context, true);
        }

      } else {
        throw Exception("Approve failed");
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to approve order"))
        );
      }
    }
  }

  Future<void> rejectOrder(int orderId) async {
    try {
      final res = await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/reject_order"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "order_id": orderId
        })
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["success"] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order rejected"))
          );
        }
        await loadOrders();
      } else {
        throw Exception("Reject failed");
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to reject order"))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green.shade700,
        title: const Text(
          "Order Approval",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      body: SafeArea(
        child: Stack(
          children: [

            Center(
              child: Opacity(
                opacity: 0.15,
                child: Image.asset(
                  "assets/images/logo_icon.png",
                  width: MediaQuery.of(context).size.width * 0.85,
                ),
              ),
            ),

            loading
                ? const Center(child: CircularProgressIndicator())
                : orders.isEmpty
                    ? const Center(child: Text("No orders to review"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length,
                        itemBuilder: (context, index){

                          final order = orders[index];
                          final items = order["items"] ?? [];

                          // 🔥 FIX: ensure int
                          final int orderId = int.tryParse(order["id"].toString()) ?? 0;

                          return Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            margin: const EdgeInsets.only(bottom:16),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [

                                  Text(
                                    "Order #${order["id"]}",
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold
                                    ),
                                  ),

                                  const SizedBox(height: 10),

                                  ...items.map<Widget>((item){
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom:6),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.qr_code, size:16, color: Colors.green),
                                          const SizedBox(width:6),
                                          Expanded(
                                            child: Text(
                                              "${item["product"] ?? "Unknown"} - ${item["profile_name"] ?? "Unknown"}",
                                              style: const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),

                                  if (order["qr_code"] != null && order["status"] == "approved") ...[
                                    const SizedBox(height: 12),
                                    const Text(
                                      "QR Code:",
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 6),
                                    Image.network(order["qr_code"], height: 120),
                                  ],

                                  const SizedBox(height: 15),

                                  Row(
                                    children: [

                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green.shade700,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8)
                                            )
                                          ),
                                          onPressed: orderId == 0 ? null : () => approveOrder(orderId),
                                          child: const Text("Approve"),
                                        ),
                                      ),

                                      const SizedBox(width:10),

                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red.shade700,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(8)
                                            )
                                          ),
                                          onPressed: orderId == 0 ? null : () => rejectOrder(orderId),
                                          child: const Text("Reject"),
                                        ),
                                      ),

                                    ],
                                  )

                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}