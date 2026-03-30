const db = require("./services/db");

// ✅ CORS HEADERS (PRODUCTION SAFE)
const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {

  // 🔥 HANDLE PREFLIGHT (REQUIRED)
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: "",
    };
  }

  // 🔒 ONLY ALLOW POST (extra safety)
  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: "Method not allowed" }),
    };
  }

  try {

    // ✅ SAFE PARSE
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

    // 🔥 QUERY
    const result = await db.query(
      `
      SELECT id, name
      FROM profiles
      WHERE user_id = $1
      ORDER BY name ASC
      `,
      [user_id]
    );

    // ✅ SUCCESS RESPONSE
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

    // ❗ IMPORTANT: still return headers on error
    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        error: "Server error",
      }),
    };

  }
};