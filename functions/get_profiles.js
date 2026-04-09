const db = require("./services/db");

// ✅ CORS HEADERS (PRODUCTION SAFE)
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
      body: "",
    };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: "Method not allowed" }),
    };
  }

  try {

    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch (e) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Invalid JSON" }),
      };
    }

    const { user_id } = body;

    if (!user_id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Missing user_id" }),
      };
    }

    const result = await db.query(
      `
      SELECT id, name, qr_token
      FROM profiles
      WHERE user_id = $1
      ORDER BY name ASC
      `,
      [user_id]
    );

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        profiles: result.rows || [],
      }),
    };

  } catch (err) {

    console.error("get-profiles error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        error: "Server error",
      }),
    };

  }
};