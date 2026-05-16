// functions/rsm_list_agents.js
const db = require("./services/db");
const { requireRsm } = require("./_adminAuth");

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
    const auth = await requireRsm(event);
    if (auth.error) {
      return reply(401, { success: false, error: "Unauthorized" });
    }

    // 🔑 Resolve caller (RSM)
    // 🧠 Pull agents for this RSM’s agency only
    const agentsRes = await db.query(
      `
      SELECT
        id,
        name,
        email
      FROM agents
      WHERE rsm_id = $1
        AND role = 'agent'
        AND active = TRUE
      ORDER BY name, email
      `,
      [auth.rsm.id]
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
