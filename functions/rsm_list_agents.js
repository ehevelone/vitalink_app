// functions/rsm_list_agents.js
const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    // 🔐 AUTH CONTEXT (adjust if your auth payload differs)
    const auth = event.headers.authorization;
    if (!auth) {
      return reply(401, { success: false, error: "Unauthorized" });
    }

    // 🔑 Resolve caller (RSM)
    const rsmRes = await db.query(
      `
      SELECT id, role, agency_id
      FROM agents
      WHERE auth_token = $1
      LIMIT 1
      `,
      [auth.replace("Bearer ", "")]
    );

    if (!rsmRes.rows.length) {
      return reply(401, { success: false, error: "Invalid user" });
    }

    const rsm = rsmRes.rows[0];

    if (rsm.role !== "rsm") {
      return reply(403, { success: false, error: "Access denied" });
    }

    // 🧠 Pull agents for this RSM’s agency only
    const agentsRes = await db.query(
      `
      SELECT
        id,
        name,
        email
      FROM agents
      WHERE agency_id = $1
        AND role = 'agent'
        AND active = TRUE
      ORDER BY name, email
      `,
      [rsm.agency_id]
    );

    return reply(200, {
      success: true,
      count: agentsRes.rows.length,
      agents: agentsRes.rows,
    });
  } catch (err) {
    console.error("❌ rsm_list_agents error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};
