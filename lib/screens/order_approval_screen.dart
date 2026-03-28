import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OrderApprovalScreen extends StatefulWidget {
  const OrderApprovalScreen({super.key});

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

  // 🔥 LOAD PENDING ORDERS
  Future<void> loadOrders() async {

    try{

      final res = await http.get(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/get_pending_orders")
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

  // 🔥 APPROVE ORDER
  Future<void> approveOrder(int orderId) async {

    try{

      await http.post(
        Uri.parse("https://vitalink-app.netlify.app/.netlify/functions/approve_order"),
        headers: {"Content-Type":"application/json"},
        body: jsonEncode({
          "order_id": orderId
        })
      );

      // reload after approval
      loadOrders();

    } catch(e){
      debugPrint("Approve failed");
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text("Pending Orders"),
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
                              return Text(
                                "${item["product"]} - ${item["profile_name"]}"
                              );
                            }).toList(),

                            const SizedBox(height: 15),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => approveOrder(order["id"]),
                                child: const Text("Approve & Generate QR"),
                              ),
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