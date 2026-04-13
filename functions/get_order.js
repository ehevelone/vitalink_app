const db = require("./services/db");

const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");
    const { order_id } = body;

    if (!order_id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({
          success: false,
          error: "Missing order_id"
        })
      };
    }

    console.log("GET ORDER REQUEST:", order_id);

    // 🔥 REAL QUERY
    const result = await db.query(
      `
      SELECT id, qr, items
      FROM public.orders
      WHERE id = $1
      LIMIT 1
      `,
      [order_id]
    );

    if (!result.rows.length) {
      return {
        statusCode: 404,
        headers,
        body: JSON.stringify({
          success: false,
          error: "Order not found"
        })
      };
    }

    const order = result.rows[0];

    // 🔥 SAFETY PARSE (if stored as string)
    if (typeof order.qr === "string") {
      order.qr = JSON.parse(order.qr);
    }

    if (typeof order.items === "string") {
      order.items = JSON.parse(order.items);
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        order
      })
    };

  } catch (err) {

    console.error("get_order error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        error: err.message
      })
    };
  }
};