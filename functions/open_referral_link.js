const db = require("./services/db");
const {
  clean,
  ensureReferralSchema,
  reply,
} = require("./services/referral-center");

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (!["GET", "POST"].includes(event.httpMethod)) {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureReferralSchema();

    const params = event.queryStringParameters || {};
    const body = event.httpMethod === "POST"
      ? JSON.parse(event.body || "{}")
      : {};
    const token = clean(params.r || params.token || body.token);

    if (!token) {
      return reply(400, { success: false, error: "Missing referral link." });
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
        r.public_token,
        CONCAT_WS(' ', u.first_name, u.last_name) AS referring_client,
        a.name AS agent_name,
        a.agency_name,
        a.email AS agent_email,
        a.phone AS agent_phone
      FROM agent_referral_invites r
      JOIN users u ON u.id = r.referring_user_id
      JOIN agents a ON a.id = r.agent_id
      WHERE r.public_token = $1
      LIMIT 1
      `,
      [token]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "Referral link not found." });
    }

    const referral = result.rows[0];

    await db.query(
      `
      UPDATE agent_referral_invites
      SET opened_at = COALESCE(opened_at, NOW()),
          updated_at = NOW()
      WHERE public_token = $1
      `,
      [token]
    );

    return reply(200, {
      success: true,
      referral: {
        name: referral.referral_name,
        phone: referral.referral_phone,
        email: referral.referral_email,
        relationship: referral.relationship,
        reason: referral.reason,
      },
      referringClient: referral.referring_client || "A VitaLink user",
      agent: {
        name: referral.agent_name || "their insurance agent",
        agencyName: referral.agency_name,
        email: referral.agent_email,
        phone: referral.agent_phone,
      },
    });
  } catch (err) {
    console.error("open_referral_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
