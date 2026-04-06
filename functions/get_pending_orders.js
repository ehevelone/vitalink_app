const db = require("./services/db");

exports.handler = async (event) => {

  // ✅ CORS
  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    let body = {};

    try {
      body = JSON.parse(event.body || "{}");
    } catch (e) {
      body = {};
    }

    const order_id = body.order_id || body.request_id;

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

    // ✅ GET ORDER (expects qr already stored)
    const result = await db.query(
      `
      SELECT id, qr
      FROM public.order_requests
      WHERE id = $1
      LIMIT 1
      `,
      [order_id]
    );

    if (!result.rows.length) {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          success: false,
          error: "Order not found"
        })
      };
    }

    const order = result.rows[0];

    let qr = [];

    try {
      qr = typeof order.qr === "string"
        ? JSON.parse(order.qr)
        : order.qr;
    } catch {
      qr = [];
    }

    if (!qr || qr.length === 0) {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          success: false,
          error: "No QR data"
        })
      };
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        order: {
          id: order.id,
          qr: qr
        }
      })
    };

  } catch (err) {
    console.error("get_order error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        error: "Server error"
      })
    };
  }
};