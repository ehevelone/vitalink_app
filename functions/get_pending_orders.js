const db = require("./services/db");

exports.handler = async (event) => {

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
    } catch {}

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

    // 🔥 NEW SYSTEM — GET ORDER (profiles only)
    const orderRes = await db.query(
      `
      SELECT id, profiles
      FROM public.orders
      WHERE id = $1
      LIMIT 1
      `,
      [order_id]
    );

    if (!orderRes.rows.length) {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          success: false,
          error: "Order not found"
        })
      };
    }

    let profileIds = orderRes.rows[0].profiles;

    try {
      profileIds = typeof profileIds === "string"
        ? JSON.parse(profileIds)
        : profileIds;
    } catch {
      profileIds = [];
    }

    if (!profileIds || profileIds.length === 0) {
      return {
        statusCode: 200,
        headers,
        body: JSON.stringify({
          success: false,
          error: "No profiles found"
        })
      };
    }

    // 🔥 GET QR TOKENS FROM PROFILES
    const result = await db.query(
      `
      SELECT id, name, qr_token
      FROM profiles
      WHERE id = ANY($1)
      `,
      [profileIds]
    );

    const qr = result.rows.map(p => ({
      profile: p.name,
      profile_id: p.id,
      qr_url: `https://myvitalink.app/emergency.html?token=${p.qr_token}`
    }));

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        order: {
          id: order_id,
          qr
        }
      })
    };

  } catch (err) {
    console.error("get_pending_orders error:", err);

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