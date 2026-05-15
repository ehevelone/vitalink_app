// @ts-nocheck

const db = require("./services/db");
const {
  syncAppClientToCrm,
} = require("./services/crm-sync");

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

function buildTaskTitle(text) {
  const firstLine = text.split(/\r?\n/).find(line => line.trim()) || text;
  const trimmed = firstLine.trim();
  return trimmed.length > 80 ? `${trimmed.slice(0, 77)}...` : trimmed;
}

async function syncToCrm({ agentId, clientId, itemType, text, appItemId }) {
  const crm = await syncAppClientToCrm({ agentId, clientId });

  if (!crm.success) {
    return crm;
  }

  if (itemType === "task") {
    const task = await db.query(
      `
      INSERT INTO crm_tasks (
        agent_id,
        client_id,
        title,
        notes,
        due_date,
        priority,
        status,
        source_app_item_id
      )
      VALUES ($1,$2,$3,$4,NULL,'Medium','Open',$5)
      RETURNING *
      `,
      [
        crm.crmAgentId,
        crm.crmClientId,
        buildTaskTitle(text),
        text,
        appItemId,
      ]
    );

    return {
      success: true,
      type: "task",
      clientId: crm.crmClientId,
      task: task.rows[0],
      clientMatched: crm.action === "updated",
      clientAction: crm.action,
    };
  }

  const note = await db.query(
    `
    INSERT INTO crm_client_notes (agent_id, client_id, note, source, source_app_item_id)
    VALUES ($1,$2,$3,'VitaLink App',$4)
    RETURNING *
    `,
    [crm.crmAgentId, crm.crmClientId, text, appItemId]
  );

  return {
    success: true,
    type: "note",
    clientId: crm.crmClientId,
    note: note.rows[0],
    clientMatched: crm.action === "updated",
    clientAction: crm.action,
  };
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

    const crmSync = await syncToCrm({
      agentId,
      clientId,
      itemType,
      text,
      appItemId: result.rows[0].id,
    });

    if (!crmSync.success) {
      console.error("save_agent_item CRM sync failed:", crmSync);

      await db.query(
        `
        DELETE FROM agent_client_items
        WHERE id = $1
        `,
        [result.rows[0].id]
      );

      return reply(500, {
        success: false,
        error: crmSync.error || "CRM sync failed",
        crm_sync: crmSync,
      });
    }

    console.log("save_agent_item CRM sync complete:", {
      itemType,
      appItemId: result.rows[0].id,
      crmClientId: crmSync.clientId,
      clientAction: crmSync.clientAction,
    });

    return reply(200, {
      success: true,
      item: result.rows[0],
      crm_sync: crmSync,
    });
  } catch (err) {
    console.error("save_agent_item error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
