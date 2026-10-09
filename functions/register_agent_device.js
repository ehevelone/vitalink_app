const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");
const { ensureAgentDevicesSchema } = require("./services/agent-devices");
const { requestLanguage } = require("./services/notification-language");

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
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    let body;
    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return reply(400, { success: false, error: "Invalid JSON body" });
    }

    const { agentId, agentSessionToken, deviceToken, fcmToken, platform } = body;
    const token = String(deviceToken || fcmToken || "").trim();
    const numericAgentId = Number(agentId);
    if (!Number.isInteger(numericAgentId) || numericAgentId <= 0 || !token) {
      return reply(400, { success: false, error: "Missing agentId or token" });
    }

    const agent = await verifyAgentSession({
      agentId: numericAgentId,
      token: agentSessionToken,
    });
    if (!agent) return reply(403, { success: false, error: "Unauthorized" });

    await ensureAgentDevicesSchema();
    const client = await db.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT pg_advisory_xact_lock(hashtext($1))", [
        `agent-device:${token}`,
      ]);
      const result = await client.query(
        `INSERT INTO agent_devices
          (agent_id, device_token, platform, push_status, created_at, updated_at, app_language)
         VALUES ($1,$2,$3,'registered',NOW(),NOW(),$4)
         ON CONFLICT (device_token) DO UPDATE SET
           agent_id=EXCLUDED.agent_id,
           platform=EXCLUDED.platform,
           push_status='registered',
           last_push_error=NULL,
           app_language=COALESCE(EXCLUDED.app_language, agent_devices.app_language),
           updated_at=NOW()
         RETURNING id, agent_id, platform, push_status, updated_at`,
        [numericAgentId, token, platform || "unknown", requestLanguage(event, body)]
      );
      await client.query("COMMIT");
      return reply(200, { success: true, device: result.rows[0] });
    } catch (error) {
      await client.query("ROLLBACK").catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error("register_agent_device error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
