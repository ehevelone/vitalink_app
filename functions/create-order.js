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

    const user_id = body.user_id;
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

    // 🔥 CRITICAL FIX: ENSURE PROFILES BELONG TO USER
    const result = await db.query(
      `
      SELECT id, name, qr_token
      FROM profiles
      WHERE user_id = $1
        AND id = ANY($2::uuid[])
      `,
      [user_id, profiles]
    );

    if (!result.rows.length) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error: "No valid profiles found for user" })
      };
    }

    const qr = result.rows.map(p => ({
      profile: p.name,
      profile_id: p.id,
      qr_url: `https://myvitalink.app/emergency.html?token=${p.qr_token}`
    }));

    // 🧾 SAVE ORDER
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