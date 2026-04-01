const db = require("./services/db");

exports.handler = async (event) => {

  // 🔥 CORS
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

    // 🔒 SAFE PARSE
    if (!event.body) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Missing body" })
      };
    }

    let body;
    try {
      body = JSON.parse(event.body);
    } catch {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Invalid JSON" })
      };
    }

    const order_id = body.order_id;

    if (!order_id) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Missing order_id" })
      };
    }

    // 🔍 GET EXISTING QR (DO NOT TOUCH IT)
    const result = await db.query(
      `
      SELECT qr_code
      FROM public.order_requests
      WHERE id = $1
      LIMIT 1
      `,
      [order_id]
    );

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ success:false, error:"Order not found" })
      };
    }

    const qr_code = result.rows[0].qr_code;

    // ✅ APPROVE ONLY
    await db.query(
      `
      UPDATE public.order_requests
      SET
        status = 'approved',
        approved_at = NOW()
      WHERE id = $1
      `,
      [order_id]
    );

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        qr_code: qr_code   // 🔥 RETURN EXISTING QR
      })
    };

  } catch (err) {
    console.error("approve_order error:", err);

    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success:false,
        error:"Server error"
      })
    };
  }
};