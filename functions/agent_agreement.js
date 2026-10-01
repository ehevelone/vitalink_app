const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");

const VERSION = "2026-09-30";
const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    const body = JSON.parse(event.body || "{}");
    const agent = await verifyAgentSession({
      agentId: body.agentId,
      token: body.agentSessionToken,
    });
    if (!agent) return reply(403, { success: false, error: "Unauthorized" });

    await db.query(`ALTER TABLE agents ADD COLUMN IF NOT EXISTS agent_agreement_version TEXT, ADD COLUMN IF NOT EXISTS agent_agreement_accepted_at TIMESTAMPTZ`);
    await db.query(`CREATE TABLE IF NOT EXISTS agent_agreement_events (
      id BIGSERIAL PRIMARY KEY,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      agreement_version TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )`);

    if (body.action === "accept") {
      if (body.agentAttestation !== true) {
        return reply(400, { success: false, error: "Agent attestation is required" });
      }
      await db.query(
        `UPDATE agents SET agent_agreement_version=$1, agent_agreement_accepted_at=NOW() WHERE id=$2`,
        [VERSION, agent.id]
      );
      await db.query(
        `INSERT INTO agent_agreement_events (agent_id, agreement_version) VALUES ($1,$2)`,
        [agent.id, VERSION]
      );
      return reply(200, { success: true, current: true, version: VERSION });
    }

    const result = await db.query("SELECT agent_agreement_version FROM agents WHERE id=$1", [agent.id]);
    return reply(200, {
      success: true,
      current: result.rows[0]?.agent_agreement_version === VERSION,
      version: VERSION,
    });
  } catch (err) {
    console.error("agent_agreement error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
