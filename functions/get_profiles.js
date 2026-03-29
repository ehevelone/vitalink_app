const db = require("./services/db");

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

exports.handler = async (event) => {

  // 🔥 HANDLE PREFLIGHT
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: "",
    };
  }

  try {

    const { user_id } = JSON.parse(event.body || "{}");

    if (!user_id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Missing user_id" }),
      };
    }

    const result = await db.query(
      `
      SELECT id, name
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
        profiles: result.rows
      })
    };

  } catch (err) {

    console.error("get-profiles error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({ error: "Server error" })
    };

  }

};