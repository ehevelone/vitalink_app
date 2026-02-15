// netlify/functions/resolve_agent_code.js
const db = require("./services/db");

/**
 * Resolve an agent unlock code during USER registration.
 * Validates active agent and returns agent profile info.
 */
exports.handler = async (event) => {
  try {
    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Method not allowed" }),
      };
    }

    const { code } = JSON.parse(event.body || "{}");

    if (!code) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Missing agent code" }),
      };
    }

    // 🔍 Lookup agent by unlock_code
    const result = await db.query(
      `
      SELECT id, name, email, phone, active
      FROM agents
      WHERE unlock_code = $1
      LIMIT 1
      `,
      [code.trim()]
    );

    if (!result.rows.length) {
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Invalid agent code" }),
      };
    }

    const agent = result.rows[0];

    if (!agent.active) {
      return {
        statusCode: 403,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Agent inactive" }),
      };
    }

    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        success: true,
        agent: {
          id: agent.id,
          name: agent.name,
          email: agent.email,
          phone: agent.phone,
        },
      }),
    };
  } catch (err) {
    console.error("❌ resolve_agent_code error:", err);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success: false, error: "Server error" }),
    };
  }
};
