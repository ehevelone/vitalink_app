const db = require("./services/db");

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS"
      },
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");
    const request_id = body.request_id;

    const result = await db.query(
      `
      SELECT id, items, status, qr_code
      FROM public.order_requests
      WHERE id = $1
      LIMIT 1
      `,
      [request_id]
    );

    if (result.rows.length === 0) {
      return {
        statusCode: 200,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:true, orders:[] })
      };
    }

    // 🔥 FIX: parse + normalize keys
    const orders = result.rows.map(order => {

      let items = [];

      try {
        items = typeof order.items === "string"
          ? JSON.parse(order.items)
          : order.items;
      } catch (e) {
        items = [];
      }

      // 🔥 normalize keys to match Flutter
      items = items.map(i => ({
        product: i.name || i.product || "Unknown",
        profile_name: i.profile || i.profile_name || "Unknown"
      }));

      return {
        ...order,
        items
      };
    });

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        orders: orders
      })
    };

  } catch (err) {
    console.error("get_pending_orders error:", err);

    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({ success:false })
    };
  }
};