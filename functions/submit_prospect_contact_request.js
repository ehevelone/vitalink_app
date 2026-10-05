const crypto = require("crypto");
const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");
const { ensureReferralSchema, reply, sendReferralPush } = require("./services/referral-center");
const { CONTACT_REQUEST_VERSION, TEMPLATES, ensureProspectMarketingSchema } = require("./services/prospect-marketing");

const VALID_CHANNELS = new Set(["call", "text", "email"]);

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    const body = JSON.parse(event.body || "{}");
    const userId = body.userId || body.user_id;
    if (!(await verifyUserSession(userId, body.sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    const userResult = await db.query(
      "SELECT id, first_name, last_name, email, phone FROM users WHERE id=$1 LIMIT 1",
      [userId]
    );
    const user = userResult.rows[0];
    if (!user) return reply(404, { success: false, error: "Account not found." });

    const deliveryId = String(body.deliveryId || "");
    const channels = [...new Set(Array.isArray(body.channels) ? body.channels.map(String) : [])]
      .filter((channel) => VALID_CHANNELS.has(channel));
    if (!channels.length) return reply(400, { success: false, error: "Choose how you would like to be contacted." });

    await ensureProspectMarketingSchema();
    await ensureReferralSchema();
    const deliveryResult = await db.query(
      `SELECT d.*, a.name AS agent_name
       FROM prospect_marketing_deliveries d
       JOIN agents a ON a.id=d.agent_id
       WHERE d.id=$1 AND d.user_id=$2 AND d.status='sent'
       LIMIT 1`,
      [deliveryId, userId]
    );
    if (!deliveryResult.rows.length) return reply(404, { success: false, error: "This message is no longer available." });
    const delivery = deliveryResult.rows[0];
    const template = TEMPLATES[delivery.template_id];
    if (!template) return reply(400, { success: false, error: "Unknown message." });

    const existing = await db.query("SELECT id FROM prospect_contact_requests WHERE delivery_id=$1 LIMIT 1", [deliveryId]);
    if (existing.rows.length) return reply(200, { success: true, alreadySubmitted: true });

    const requestText = `${delivery.agent_name} may contact me about ${template.topic} using: ${channels.join(", ")}.`;
    const requestId = crypto.randomUUID();
    const referralId = crypto.randomUUID();
    await db.query("BEGIN");
    try {
      await db.query(
        `INSERT INTO prospect_contact_requests
          (id,delivery_id,user_id,agent_id,category,template_id,channels,
           request_text,request_version,platform)
         VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8,$9,$10)`,
        [requestId, deliveryId, userId, delivery.agent_id, delivery.category,
          delivery.template_id, JSON.stringify(channels), requestText,
          CONTACT_REQUEST_VERSION, body.platform || null]
      );
      await db.query(
        `INSERT INTO agent_referrals
          (id,agent_id,referring_user_id,referral_name,referral_phone,
           referral_email,relationship,reason,notes,source,contact_preference,
           contact_preference_submitted_at,status)
         VALUES ($1,$2,$3,$4,$5,$6,'Prospect',$7,$8,'prospect_marketing',$9,NOW(),
           'Contact Preference Submitted')`,
        [referralId, delivery.agent_id, userId,
          `${user.first_name || ""} ${user.last_name || ""}`.trim() || "VitaLink Prospect",
          user.phone || null, user.email || null, template.topic,
          `Requested contact after ${template.label}.`, channels.join(", ")]
      );
      await db.query(
        "UPDATE prospect_marketing_deliveries SET status='responded', request_submitted_at=NOW(), opened_at=COALESCE(opened_at,NOW()) WHERE id=$1",
        [deliveryId]
      );
      await db.query("COMMIT");
    } catch (error) {
      await db.query("ROLLBACK");
      throw error;
    }

    await sendReferralPush({
      recipient: { type: "agent", id: delivery.agent_id },
      referral: { id: referralId },
      title: "Prospect Contact Request",
      body: `A prospect requested ${channels.join(", ")} contact about ${template.topic}.`,
    });
    return reply(200, { success: true });
  } catch (error) {
    console.error("submit_prospect_contact_request error", error?.message);
    return reply(500, { success: false, error: "Unable to send your request." });
  }
};
