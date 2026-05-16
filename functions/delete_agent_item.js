// @ts-nocheck

const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");

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

    const agentId =
      Number(body.agentId);

    const itemId =
      Number(body.itemId);

    if (!agentId || !itemId) {
      return reply(400, {
        success: false,
        error: "Missing agent or item",
      });
    }

    const sessionAgent = await verifyAgentSession({
      agentId,
      token: body.agentSessionToken,
    });

    if (!sessionAgent) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    const deleted = await db.query(
      `
      DELETE FROM agent_client_items
      WHERE id = $1
        AND agent_id = $2
      RETURNING id, item_type
      `,
      [itemId, agentId]
    );

    if (!deleted.rows.length) {
      return reply(404, {
        success: false,
        error: "Item not found",
      });
    }

    const item =
      deleted.rows[0];

    try {
      if (item.item_type === "task") {
        await db.query(
          `
          DELETE FROM crm_tasks
          WHERE source_app_item_id = $1
          `,
          [item.id]
        );
      }

      if (item.item_type === "note") {
        await db.query(
          `
          DELETE FROM crm_client_notes
          WHERE source_app_item_id = $1
          `,
          [item.id]
        );
      }
    } catch (syncErr) {
      console.error("delete_agent_item CRM mirror delete error:", syncErr);
    }

    return reply(200, {
      success: true,
      item,
    });
  } catch (err) {
    console.error("delete_agent_item error:", err);
    return reply(500, {
      success: false,
      error: "Server error",
    });
  }
};
