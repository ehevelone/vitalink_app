const crypto = require("crypto");
const db = require("./services/db");
const {
  clean,
  createInviteCode,
  ensureSchema,
  normalizeSections,
  parseBody,
  reply,
  sendProfileShareInvitePush,
  verifyUserSession,
} = require("./services/profile-share-sync");

function normalizePhoneDigits(value) {
  const digits = String(value || "").replace(/\D/g, "");
  return digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : digits;
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") {
      return reply(405, { success: false, error: "Method Not Allowed" });
    }

    await ensureSchema();

    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const invitedEmail = clean(body.email || body.invitedEmail)?.toLowerCase();
    const invitedPhone = clean(body.phone || body.invitedPhone);
    const profileId = clean(body.profileId || body.profile_id);
    const profileName = clean(body.profileName || body.profile_name);
    const allowedSections = normalizeSections(body.allowedSections);

    if (!invitedEmail || !invitedPhone) {
      return reply(400, {
        success: false,
        error: "Enter both the email and phone number for the person you want to share with.",
      });
    }

    let recipientUserId = null;

    const phoneDigits = normalizePhoneDigits(invitedPhone);

    if (invitedEmail && phoneDigits) {
      const userRes = await db.query(
        `
        SELECT id
        FROM users
        WHERE LOWER(email) = LOWER($1)
          AND RIGHT(REGEXP_REPLACE(COALESCE(phone, ''), '\\D', '', 'g'), 10) = $2
        LIMIT 1
        `,
        [invitedEmail, phoneDigits]
      );

      recipientUserId = userRes.rows[0]?.id || null;
    }

    const inviteCode = createInviteCode();
    const status = recipientUserId ? "accepted" : "pending";

    const result = await db.query(
      `
      INSERT INTO profile_share_links (
        id,
        owner_user_id,
        recipient_user_id,
        invited_email,
        invited_phone,
        profile_id,
        profile_name,
        allowed_sections,
        status,
        invite_code,
        accepted_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8::jsonb,$9,$10,CASE WHEN $9='accepted' THEN NOW() ELSE NULL END)
      RETURNING *
      `,
      [
        crypto.randomUUID(),
        userId,
        recipientUserId,
        invitedEmail,
        invitedPhone,
        profileId || null,
        profileName,
        JSON.stringify(allowedSections),
        status,
        inviteCode,
      ]
    );

    const push = recipientUserId
      ? await sendProfileShareInvitePush({
          recipientUserId,
          inviteCode,
          profileName,
        })
      : { devicesTargeted: 0, successCount: 0, failureCount: 0 };

    return reply(200, {
      success: true,
      share: result.rows[0],
      inviteCode,
      accepted: status === "accepted",
      push,
    });
  } catch (err) {
    console.error("create_profile_share_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
