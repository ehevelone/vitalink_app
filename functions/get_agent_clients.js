// @ts-nocheck

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

    // ✅ BACK TO WORKING LOGIC (agentId)
    const { agentId } = JSON.parse(event.body || "{}");

    if (!agentId) {
      return reply(400, {
        success: false,
        error: "Missing agentId",
      });
    }

    // GET AGENT
    const agentResult = await db.query(
      `
      SELECT id, name
      FROM agents
      WHERE id = $1
      LIMIT 1
      `,
      [agentId]
    );

    if (agentResult.rows.length === 0) {
      return reply(404, {
        success: false,
        error: "Agent not found",
      });
    }

    const agent = agentResult.rows[0];

    // GET CLIENTS
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