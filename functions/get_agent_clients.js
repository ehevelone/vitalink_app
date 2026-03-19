// @ts-nocheck

const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
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

    // 🔥 GET TOKEN INSTEAD OF agent_id
    const token = event.headers.authorization;

    if (!token) {
      return reply(401, {
        success: false,
        error: "Unauthorized",
      });
    }

    // 🔥 GET AGENT FROM SESSION TOKEN
    const agentResult = await db.query(
      `
      SELECT id, first_name, last_name
      FROM rsms
      WHERE admin_session_token = $1
      LIMIT 1
      `,
      [token]
    );

    if (agentResult.rows.length === 0) {
      return reply(403, {
        success: false,
        error: "Invalid session",
      });
    }

    const agent = agentResult.rows[0];

    // 🔥 GET CLIENTS USING AGENT ID
    const clientsResult = await db.query(
      `
      SELECT 
        id,
        first_name,
        last_name,
        email,
        phone,
        active,
        profile_complete,
        last_notified_at,
        last_notified_campaign,
        last_reviewed
      FROM users
      WHERE agent_id = $1
      ORDER BY created_at DESC
      `,
      [agent.id]
    );

    return reply(200, {
      success: true,
      agent: {
        first_name: agent.first_name,
        last_name: agent.last_name,
      },
      clients: clientsResult.rows,
    });

  } catch (err) {
    console.error("get_agent_clients error:", err);

    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};