const db = require("./services/db");

exports.handler = async (event) => {

  // 🔥 HANDLE PREFLIGHT (CORS)
  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
      body: "",
    };
  }

  try {

    const { user_id } = JSON.parse(event.body || "{}");

    if (!user_id) {
      return {
        statusCode: 400,
        headers: {
          "Access-Control-Allow-Origin": "https://myvitalink.app",
        },
        body: JSON.stringify({ error: "Missing user_id" })
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
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
      },
      body: JSON.stringify({
        success: true,
        profiles: result.rows
      })
    };

  } catch (err) {

    console.error(err);

    return {
      statusCode: 500,
      headers: {
        "Access-Control-Allow-Origin": "https://myvitalink.app",
      },
      body: JSON.stringify({ error: "Server error" })
    };

  }

};