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
    const order_id = body.order_id;

    if (!order_id) {
      return {
        statusCode: 400,
        headers: {
          "Access-Control-Allow-Origin": "https://myvitalink.app"
        },
        body: JSON.stringify({
          success: false,
          error: "Missing order_id"
        })
      };
    }

    // ❌ UPDATE STATUS
    const result = await db.query(
      `
      UPDATE public.order_requests
      SET status = 'rejected'
      WHERE id = $1
      RETURNING id
      `,
      [order_id]
    );

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: {
          "Access-Control-Allow-Origin": "https://myvitalink.app"
        },
        body: JSON.stringify({
          success: false,
          error: "Order not found"
        })
      };
    }

    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app"
      },
      body: JSON.stringify({
        success: true,
        order_id: order_id
      })
    };

  } catch (err) {
    console.error("reject_order error:", err);

    return {
      statusCode: 500,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app"
      },
      body: JSON.stringify({
        success: false,
        error: "Server error"
      })
    };
  }
};