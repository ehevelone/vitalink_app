// @ts-nocheck

const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

async function ensureTable() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS agent_client_items (
      id BIGSERIAL PRIMARY KEY,
      agent_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      item_type TEXT NOT NULL CHECK (item_type IN ('note', 'task')),
      body TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_agent_client_items_agent_user_created
    ON agent_client_items (agent_id, user_id, created_at DESC)
  `);
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return reply(200, {});
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  try {
    let body = {};
    try {
      body = JSON.parse(event.body || "{}");
    } catch (_) {
      return reply(400, { success: false, error: "Invalid JSON" });
    }

    const agentId = Number(body.agentId);
    const clientId = body.clientId ? Number(body.clientId) : null;

    if (!agentId) {
      return reply(400, { success: false, error: "Missing agentId" });
    }

    await ensureTable();

    const params = [agentId];
    let clientFilter = "";

    if (clientId) {
      params.push(clientId);
      clientFilter = "AND i.user_id = $2";
    }

    const result = await db.query(
      `
      SELECT
        i.id,
        i.agent_id,
        i.user_id,
        i.item_type,
        i.body,
        i.created_at,
        u.first_name,
        u.last_name,
        u.email
      FROM agent_client_items i
      JOIN users u ON u.id = i.user_id AND u.agent_id = i.agent_id
      WHERE i.agent_id = $1
      ${clientFilter}
      ORDER BY i.created_at DESC
      LIMIT 100
      `,
      params
    );

    return reply(200, {
      success: true,
      items: result.rows,
    });
  } catch (err) {
    console.error("get_agent_items error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
