import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OrderApprovalScreen extends StatefulWidget {
  final int? requestId; // 🔥 from push

  const OrderApprovalScreen({super.key, this.requestId});

  @override
  State<OrderApprovalScreen> createState() => _OrderApprovalScreenState();
}

class _OrderApprovalScreenState extends State<OrderApprovalScreen> {

  bool loading = true;
  List orders = [];

  @override
  void initState() {
    super.initState();
    loadOrders();
  }

  // 🔥 LOAD USER-SPECIFIC ORDERS
  Future<void> loadOrders() async {

    try{

      final res = await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/get_pending_orders"),
        headers: {"Content-Type":"application/json"},
        body: jsonEncode({
          "request_id": widget.requestId // 🔥 optional filter
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

  // 🔥 APPROVE
  Future<void> approveOrder(int orderId) async {

    try{

      await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/approve_order"),
        headers: {"Content-Type":"application/json"},
        body: jsonEncode({
          "order_id": orderId
        })
      );

      loadOrders();

    } catch(e){
      debugPrint("Approve failed");
    }
  }

  // 🔥 REJECT
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

                            ...order["items"].map<Widget>((item){
                              return Padding(
                                padding: const EdgeInsets.only(bottom:4),
                                child: Text(
                                  "${item["product"]} - ${item["profile_name"]}"
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