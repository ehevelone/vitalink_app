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

    // ❌ UPDATE STATUS
    await db.query(
      `
      UPDATE public.order_requests
      SET
        status = 'rejected',
        rejected_at = NOW()
      WHERE id = $1
      `,
      [order_id]
    );

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({ success:true })
    };

  } catch (err) {
    console.error("reject_order error:", err);

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