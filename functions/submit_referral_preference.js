const crypto = require("crypto");
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

    console.log("submit_referral_preference start", {
      hasToken: Boolean(token),
      tokenTail: token ? token.slice(-6) : null,
      preference,
      hasPhone: Boolean(phone),
      hasEmail: Boolean(email),
    });

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
      FROM agent_referral_invites r
      JOIN users u ON u.id = r.referring_user_id
      JOIN agents a ON a.id = r.agent_id
      WHERE r.public_token = $1
      LIMIT 1
      `,
      [token]
    );

    if (!lookup.rows.length) {
      console.log("submit_referral_preference not_found", {
        tokenTail: token.slice(-6),
      });
      return reply(404, { success: false, error: "Referral link not found." });
    }

    const invite = lookup.rows[0];

    console.log("submit_referral_preference invite_found", {
      inviteId: invite.id,
      agentId: invite.agent_id,
      referringUserId: invite.referring_user_id,
      alreadyConverted: Boolean(invite.converted_referral_id),
    });

    if (invite.converted_referral_id) {
      console.log("submit_referral_preference already_submitted", {
        referralId: invite.converted_referral_id,
        agentId: invite.agent_id,
      });
      return reply(200, {
        success: true,
        referral: { id: invite.converted_referral_id },
        referringClient: invite.referring_client || "A VitaLink user",
        agentName: invite.agent_name,
        alreadySubmitted: true,
      });
    }

    const inserted = await db.query(
      `
      INSERT INTO agent_referrals (
        id,
        agent_id,
        referring_user_id,
        referral_name,
        referral_phone,
        referral_email,
        relationship,
        reason,
        notes,
        source,
        public_token,
        contact_preference,
        link_opened_at,
        contact_preference_submitted_at,
        status
      )
      VALUES (
        $1,$2,$3,$4,
        COALESCE(NULLIF($5, ''), $6),
        COALESCE(NULLIF($7, ''), $8),
        $9,$10,$11,$12,$13,$14,$15,NOW(),
        'Contact Preference Submitted'
      )
      RETURNING *
      `,
      [
        crypto.randomUUID(),
        invite.agent_id,
        invite.referring_user_id,
        invite.referral_name,
        phone,
        invite.referral_phone,
        email,
        invite.referral_email,
        invite.relationship,
        invite.reason,
        invite.notes,
        invite.source,
        invite.public_token,
        preference,
        invite.opened_at,
      ]
    );

    const referral = inserted.rows[0];

    console.log("submit_referral_preference referral_created", {
      referralId: referral.id,
      agentId: referral.agent_id,
      referringUserId: referral.referring_user_id,
    });

    await db.query(
      `
      UPDATE agent_referral_invites
      SET converted_referral_id = $1,
          updated_at = NOW()
      WHERE id = $2
      `,
      [referral.id, invite.id]
    );

    const referringClient = invite.referring_client || "A VitaLink user";

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
      agentName: invite.agent_name,
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
