const db = require("./services/db");
const { verifyAgentSession } = require("./services/agent-auth");
const {
  clean,
  ensureReferralSchema,
  reply,
} = require("./services/referral-center");

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

    const agent = await verifyAgentSession({
      agentId,
      token: clean(body.agentSessionToken),
    });

    if (!agent) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!referralId) {
      return reply(400, { success: false, error: "Missing referral id." });
    }

    const result = await db.query(
      `
      DELETE FROM agent_referrals
      WHERE id = $1
        AND agent_id = $2
      RETURNING id
      `,
      [referralId, agent.id]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "Referral not found." });
    }

    return reply(200, { success: true, deletedReferralId: referralId });
  } catch (err) {
    console.error("delete_agent_referral error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
