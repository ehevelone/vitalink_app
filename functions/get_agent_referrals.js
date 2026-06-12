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
    const agent = await verifyAgentSession({
      agentId,
      token: clean(body.agentSessionToken),
    });

    if (!agent) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const result = await db.query(
      `
      SELECT
        r.id,
        r.referral_name,
        r.referral_phone,
        r.referral_email,
        r.relationship,
        r.reason,
        r.notes,
        r.contact_preference,
        r.status,
        r.submitted_at,
        r.link_opened_at,
        r.contact_preference_submitted_at,
        r.agent_first_opened_at,
        r.agent_first_contacted_at,
        r.appointment_scheduled_at,
        r.client_added_at,
        r.closed_at,
        CONCAT_WS(' ', u.first_name, u.last_name) AS referring_client,
        u.email AS referring_client_email
      FROM agent_referrals r
      JOIN users u ON u.id = r.referring_user_id
      WHERE r.agent_id = $1
      ORDER BY r.submitted_at DESC
      `,
      [agent.id]
    );

    await db.query(
      `
      UPDATE agent_referrals
      SET agent_first_opened_at = COALESCE(agent_first_opened_at, NOW())
      WHERE agent_id = $1
      `,
      [agent.id]
    );

    const rows = result.rows;
    const total = rows.length;
    const contacted = rows.filter((r) =>
      ["Agent Contacted", "Appointment Scheduled", "Client Added", "Closed"].includes(r.status)
    ).length;
    const appointments = rows.filter((r) =>
      ["Appointment Scheduled", "Client Added", "Closed"].includes(r.status)
    ).length;
    const converted = rows.filter((r) => r.status === "Client Added").length;
    const pending = rows.filter((r) =>
      ["Introduction Sent", "Referral Link Opened", "Contact Preference Submitted"].includes(r.status)
    ).length;

    return reply(200, {
      success: true,
      referrals: rows,
      metrics: {
        total,
        contactRate: total ? contacted / total : 0,
        appointmentRate: total ? appointments / total : 0,
        conversionRate: total ? converted / total : 0,
        pending,
      },
    });
  } catch (err) {
    console.error("get_agent_referrals error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
