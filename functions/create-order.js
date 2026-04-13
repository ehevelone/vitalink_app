const db = require("./services/db");

exports.handler = async (event) => {

  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  try {

    const body = JSON.parse(event.body || "{}");

    const user_id = body.user_id; // 🔥 ADDED
    const profiles = body.profiles;
    const items = body.items || [];

    if (!user_id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error: "Missing user_id" })
      };
    }

    if (!profiles || !Array.isArray(profiles) || profiles.length === 0) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error: "Missing profiles" })
      };
    }

    // 🔥 GET EXISTING QR TOKENS
    const result = await db.query(
      `
      SELECT id, name, qr_token
      FROM profiles
      WHERE id = ANY($1::uuid[])
      `,
      [profiles]
    );

    const qr = result.rows.map(p => ({
      profile: p.name,
      profile_id: p.id,
      qr_url: `https://myvitalink.app/emergency.html?token=${p.qr_token}`
    }));

    // 🧾 SAVE ORDER (FIXED WITH user_id)
    const orderRes = await db.query(
      `
      INSERT INTO public.orders (user_id, profiles, items, qr, status, created_at)
      VALUES ($1, $2, $3, $4, 'created', NOW())
      RETURNING id
      `,
      [
        user_id,
        JSON.stringify(profiles),
        JSON.stringify(items),
        JSON.stringify(qr)
      ]
    );

    const order_id = orderRes.rows[0].id;

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        order_id
      }),
    };

  } catch (err) {
    console.error("❌ create-order error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success:false,
        error: err.message
      }),
    };
  }
};