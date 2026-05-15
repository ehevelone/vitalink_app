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
    const clientId = Number(body.clientId);
    const itemType = (body.itemType || "").toString().trim().toLowerCase();
    const text = (body.text || body.body || "").toString().trim();

    if (!agentId || !clientId) {
      return reply(400, { success: false, error: "Missing agent or client" });
    }

    if (!["note", "task"].includes(itemType)) {
      return reply(400, { success: false, error: "Invalid item type" });
    }

    if (!text) {
      return reply(400, { success: false, error: "Text is required" });
    }

    const clientCheck = await db.query(
      "SELECT id FROM users WHERE id = $1 AND agent_id = $2 LIMIT 1",
      [clientId, agentId]
    );

    if (!clientCheck.rows.length) {
      return reply(403, { success: false, error: "Unauthorized client" });
    }

    await ensureTable();

    const result = await db.query(
      `
      INSERT INTO agent_client_items (agent_id, user_id, item_type, body)
      VALUES ($1, $2, $3, $4)
      RETURNING id, agent_id, user_id, item_type, body, created_at
      `,
      [agentId, clientId, itemType, text]
    );

    return reply(200, {
      success: true,
      item: result.rows[0],
    });
  } catch (err) {
    console.error("save_agent_item error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
