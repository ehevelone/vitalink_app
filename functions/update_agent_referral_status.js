const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");
const {
  clean,
  ensureReferralSchema,
  reply,
} = require("./services/referral-center");

const VALID_STATUSES = new Set([
  "Introduction Sent",
  "Referral Link Opened",
  "Contact Preference Submitted",
  "Contacted",
  "Appointment Scheduled",
  "Client Added",
  "Closed",
]);

function statusTimestampColumn(status) {
  if (status === "Contacted") return "agent_first_contacted_at";
  if (status === "Appointment Scheduled") return "appointment_scheduled_at";
  if (status === "Client Added") return "client_added_at";
  if (status === "Closed") return "closed_at";
  return null;
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureReferralSchema();

    const body = JSON.parse(event.body || "{}");
    const agentId = clean(body.agentId || body.agent_id);
    const referralId = clean(body.referralId || body.referral_id);
    const status = clean(body.status);

    const agent = await verifyAgentSession({
      agentId,
      token: clean(body.agentSessionToken),
    });

    if (!agent) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!referralId || !VALID_STATUSES.has(status)) {
      return reply(400, { success: false, error: "Invalid referral status." });
    }

    const stampColumn = statusTimestampColumn(status);
    const stampSql = stampColumn
      ? `, ${stampColumn} = COALESCE(${stampColumn}, NOW())`
      : "";

    const result = await db.query(
      `
      UPDATE agent_referrals
      SET status = $1,
          updated_at = NOW()
          ${stampSql}
      WHERE id = $2
        AND agent_id = $3
      RETURNING *
      `,
      [status, referralId, agent.id]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "Referral not found." });
    }

    return reply(200, { success: true, referral: result.rows[0] });
  } catch (err) {
    console.error("update_agent_referral_status error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
