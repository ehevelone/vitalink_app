const db = require("./services/db");

// ✅ CORS HEADERS (PRODUCTION SAFE)
const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
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
    } catch {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Invalid JSON" }),
      };
    }

    const ids =
      Array.isArray(body.profiles) ? body.profiles :
      body.id ? [body.id] :
      [];

    if (!ids.length) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Missing id(s)" }),
      };
    }

    const result = await db.query(
      `
      SELECT id, name, qr_token
      FROM profiles
      WHERE id = ANY($1)
      `,
      [ids]
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