const db = require("./services/db");
const {
  clean,
  ensureReferralSchema,
  reply,
  verifyUserSession,
} = require("./services/referral-center");

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureReferralSchema();

    const body = JSON.parse(event.body || "{}");
    const userId = clean(body.userId || body.user_id);
    const user = await verifyUserSession(userId, clean(body.sessionToken));

    if (!user) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const result = await db.query(
      `
      SELECT
        id,
        referral_name,
        referral_phone,
        referral_email,
        relationship,
        reason,
        contact_preference,
        status,
        link_opened_at,
        contact_preference_submitted_at,
        submitted_at
      FROM agent_referrals
      WHERE referring_user_id = $1
      ORDER BY submitted_at DESC
      `,
      [user.id]
    );

    return reply(200, { success: true, referrals: result.rows });
  } catch (err) {
    console.error("get_my_referrals error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
