// functions/export_agent_clients.js
const db = require("./services/db");
const { requireAdminOrRsm } = require("./_adminAuth");
const { verifyAgentSession } = require("./services/agent-auth");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    const agentId = event.queryStringParameters?.agent_id;
    if (!agentId) {
      return reply(400, {
        success: false,
        error: "Missing agent_id",
      });
    }

    const agentSessionToken =
      event.headers["x-agent-session"] ||
      event.headers["X-Agent-Session"];

    let authorized = false;

    if (agentSessionToken) {
      const agent = await verifyAgentSession({
        agentId,
        token: agentSessionToken,
      });
      authorized = Boolean(agent);
    } else {
      const auth = await requireAdminOrRsm(event);

      if (!auth.error && auth.user.role === "admin") {
        authorized = true;
      }

      if (!auth.error && auth.user.role === "rsm") {
        const owner = await db.query(
          "SELECT id FROM agents WHERE id = $1 AND rsm_id = $2 LIMIT 1",
          [agentId, auth.user.id]
        );
        authorized = owner.rows.length > 0;
      }
    }

    if (!authorized) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    // 🔍 Pull agent + client emails + device platforms
    const result = await db.query(
      `
      SELECT
        a.email AS agent_email,
        u.email AS client_email,
        ARRAY_AGG(DISTINCT ud.platform) AS devices
      FROM agents a
      JOIN agent_users au ON au.agent_id = a.id
      JOIN users u ON u.id = au.user_id
      LEFT JOIN user_devices ud
        ON ud.user_id = u.id
       AND ud.agent_id = a.id
      WHERE a.id = $1
      GROUP BY a.email, u.email
      ORDER BY u.email;
      `,
      [agentId]
    );

    return reply(200, {
      success: true,
      agent_id: agentId,
      count: result.rows.length,
      clients: result.rows,
    });
  } catch (err) {
    console.error("❌ export_agent_clients error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};
