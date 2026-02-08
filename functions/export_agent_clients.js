// functions/export_agent_clients.js
const db = require("./services/db");

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
