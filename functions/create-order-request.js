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

    console.log("🔥 RAW BODY:", body);

    const user_id = body.user_id;
    const cart = body.cart;

    // ✅ HARD FIX — no silent fail
    if (!user_id) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ error: "Missing user_id" })
      };
    }

    if (!cart || !Array.isArray(cart) || cart.length === 0) {
      return {
        statusCode: 400,
        headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
        body: JSON.stringify({ error: "Invalid cart" })
      };
    }

    const result = await db.query(
      `
      INSERT INTO public.order_requests (user_id, items, status)
      VALUES ($1, $2, 'pending')
      RETURNING id
      `,
      [
        user_id,
        JSON.stringify(cart)
      ]
    );

    return {
      statusCode: 200,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        success: true,
        request_id: result.rows[0].id
      })
    };

  } catch (err) {

    console.error("create-order-request error:", err);

    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://myvitalink.app" },
      body: JSON.stringify({
        error: err.message
      })
    };
  }
};