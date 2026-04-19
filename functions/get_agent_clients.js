// @ts-nocheck

const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS"
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {

    // ---------------- CORS
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    // ---------------- SAFE PARSE
    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch (e) {
      console.error("JSON parse error:", e);
      return reply(400, {
        success: false,
        error: "Invalid JSON",
      });
    }

    const { agentId } = body;

    console.log("📥 Incoming agentId:", agentId);

    if (!agentId) {
      return reply(400, {
        success: false,
        error: "Missing agentId",
      });
    }

    // ---------------- GET AGENT
    const agentResult = await db.query(
      `
      SELECT id, name
      FROM agents
      WHERE id = $1
      LIMIT 1
      `,
      [agentId]
    );

    console.log("👤 Agent query result:", agentResult.rows);

    if (agentResult.rows.length === 0) {
      return reply(404, {
        success: false,
        error: "Agent not found",
      });
    }

    const agent = agentResult.rows[0];

    // ---------------- GET CLIENTS (🔥 UPDATED)
    const clientsResult = await db.query(
      `
      SELECT 
        u.id,
        u.first_name,
        u.last_name,
        u.email,
        u.phone,
        u.active,
        u.profile_complete,
        u.last_notified_at,
        u.last_notified_campaign,
        u.last_reviewed,
        CASE 
          WHEN ud.device_token IS NOT NULL 
            AND TRIM(ud.device_token) <> '' 
          THEN TRUE 
          ELSE FALSE 
        END AS has_device
      FROM users u
      LEFT JOIN user_devices ud ON ud.user_id = u.id
      WHERE u.agent_id = $1
      ORDER BY u.created_at DESC
      `,
      [agent.id]
    );

    console.log("👥 Clients found:", clientsResult.rows.length);

    // ---------------- RESPONSE
    return reply(200, {
      success: true,
      agent: {
        id: agent.id,
        name: agent.name,
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