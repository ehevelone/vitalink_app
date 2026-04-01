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

  bool _loadedOnce = false; // ✅ ADDED (prevents duplicate calls)

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_loadedOnce) return; // ✅ FIX
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

    try{

      final res = await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/get_pending_orders"),
        headers: {"Content-Type":"application/json"},
        body: jsonEncode({
          "request_id": requestId
        })
      );

      final data = jsonDecode(res.body);

      if(data["success"]){
        setState(() {
          orders = data["orders"];
          loading = false;
        });
      }

    } catch(e){
      setState(() => loading = false);
    }
  }

  Future<void> approveOrder(int orderId) async {

    try{

      final res = await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/approve_order"),
        headers: {"Content-Type":"application/json"},
        body: jsonEncode({
          "order_id": orderId
        })
      );

      if(res.statusCode == 200){

        if(mounted){
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order approved"))
          );

          await loadOrders(); // ✅ FIX (refresh instead of pop)
        }

      } else {
        throw Exception("Approve failed");
      }

    } catch(e){
      debugPrint("Approve failed: $e");

      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to approve order"))
        );
      }
    }
  }

  Future<void> rejectOrder(int orderId) async {

    try{

      await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/reject_order"),
        headers: {"Content-Type":"application/json"},
        body: jsonEncode({
          "order_id": orderId
        })
      );

      loadOrders();

    } catch(e){
      debugPrint("Reject failed");
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Order Approval"),
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(child: Text("No pending orders"))
              : ListView.builder(
                  itemCount: orders.length,
                  itemBuilder: (context, index){

                    final order = orders[index];

                    final items = order["items"] ?? []; // ✅ FIX (null safety)

                    return Card(
                      margin: const EdgeInsets.all(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
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
                                padding: const EdgeInsets.only(bottom:4),
                                child: Text(
                                  "${item["product"] ?? "Unknown"} - ${item["profile_name"] ?? "Unknown"}"
                                ),
                              );
                            }).toList(),

                            const SizedBox(height: 15),

                            Row(
                              children: [

                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green
                                    ),
                                    onPressed: () => approveOrder(order["id"]),
                                    child: const Text("Approve"),
                                  ),
                                ),

                                const SizedBox(width:10),

                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red
                                    ),
                                    onPressed: () => rejectOrder(order["id"]),
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
    );
  }
}