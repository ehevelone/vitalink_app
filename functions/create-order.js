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

    const profiles = body.profiles;
    const items = body.items || [];

    if (!profiles || !Array.isArray(profiles) || profiles.length === 0) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error: "Missing profiles" })
      };
    }

    // 🔥 GET EXISTING QR TOKENS (DO NOT REGENERATE)
    const result = await db.query(
      `
      SELECT id, name, qr_token
      FROM profiles
      WHERE id = ANY($1)
      `,
      [profiles]
    );

    const qr = result.rows.map(p => ({
      profile: p.name,
      profile_id: p.id,
      qr_url: `https://myvitalink.app/emergency.html?token=${p.qr_token}`
    }));

    // 🧾 SAVE ORDER
    const orderRes = await db.query(
      `
      INSERT INTO public.orders (profiles, items, qr, status, created_at)
      VALUES ($1, $2, $3, 'created', NOW())
      RETURNING id
      `,
      [
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
        error: "Server error"
      }),
    };
  }
};