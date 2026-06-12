const db = require("./services/db");
const {
  clean,
  ensureReferralSchema,
  reply,
  sendReferralPush,
} = require("./services/referral-center");

const VALID_PREFERENCES = new Set(["Text Message", "Phone Call", "Email"]);

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureReferralSchema();

    const body = JSON.parse(event.body || "{}");
    const token = clean(body.token);
    const preference = clean(body.contactPreference || body.preference);
    const phone = clean(body.phone);
    const email = clean(body.email).toLowerCase();

    if (!token) {
      return reply(400, { success: false, error: "Missing referral link." });
    }

    if (!VALID_PREFERENCES.has(preference)) {
      return reply(400, { success: false, error: "Choose Text Message, Phone Call, or Email." });
    }

    if ((preference === "Text Message" || preference === "Phone Call") && !phone) {
      return reply(400, { success: false, error: "Enter a phone number." });
    }

    if (preference === "Email" && !email) {
      return reply(400, { success: false, error: "Enter an email address." });
    }

    const lookup = await db.query(
      `
      SELECT
        r.*,
        CONCAT_WS(' ', u.first_name, u.last_name) AS referring_client,
        a.name AS agent_name
      FROM agent_referrals r
      JOIN users u ON u.id = r.referring_user_id
      JOIN agents a ON a.id = r.agent_id
      WHERE r.public_token = $1
      LIMIT 1
      `,
      [token]
    );

    if (!lookup.rows.length) {
      return reply(404, { success: false, error: "Referral link not found." });
    }

    const existing = lookup.rows[0];
    const updated = await db.query(
      `
      UPDATE agent_referrals
      SET referral_phone = COALESCE(NULLIF($2, ''), referral_phone),
          referral_email = COALESCE(NULLIF($3, ''), referral_email),
          contact_preference = $4,
          contact_preference_submitted_at = COALESCE(contact_preference_submitted_at, NOW()),
          status = 'Contact Preference Submitted',
          updated_at = NOW()
      WHERE id = $1
      RETURNING *
      `,
      [existing.id, phone, email, preference]
    );

    const referral = updated.rows[0];
    const referringClient = existing.referring_client || "A VitaLink user";

    const agentPush = await sendReferralPush({
      recipient: { type: "agent", id: referral.agent_id },
      referral,
      title: "New VitaLink Referral",
      body: `${referral.referral_name} preferred contact: ${preference}.`,
    });

    const clientPush = await sendReferralPush({
      recipient: { type: "user", id: referral.referring_user_id },
      referral,
      title: "Referral sent successfully",
      body: `${referral.referral_name} submitted a contact preference.`,
    });

    return reply(200, {
      success: true,
      referral,
      referringClient,
      agentName: existing.agent_name,
      push: {
        agent: agentPush,
        client: clientPush,
      },
    });
  } catch (err) {
    console.error("submit_referral_preference error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
