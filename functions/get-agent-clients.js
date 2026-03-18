const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    // CORS
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    const body = JSON.parse(event.body || "{}");
    const { agent_id } = body;

    if (!agent_id) {
      return reply(400, {
        success: false,
        error: "Missing agent_id",
      });
    }

    const result = await db.query(
      `
      SELECT 
        first_name,
        last_name,
        email,
        phone
      FROM users
      WHERE agent_id = $1
      ORDER BY created_at DESC
      `,
      [agent_id]
    );

    return reply(200, {
      success: true,
      clients: result.rows,
    });

  } catch (err) {
    console.error("get_agent_clients error:", err);

    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};