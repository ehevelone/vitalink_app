const db = require("./services/db");
const {
  clean,
  ensureSchema,
  parseBody,
  reply,
  verifyUserSession,
} = require("./services/profile-share-sync");

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
    const inviteCode = clean(body.inviteCode || body.invite_code)?.toUpperCase();

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!inviteCode) {
      return reply(400, { success: false, error: "Missing invite code" });
    }

    const result = await db.query(
      `
      UPDATE profile_share_links
      SET recipient_user_id = $1,
          status = 'accepted',
          accepted_at = COALESCE(accepted_at, NOW())
      WHERE invite_code = $2
        AND status <> 'revoked'
        AND revoked_at IS NULL
      RETURNING *
      `,
      [userId, inviteCode]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "Share invite not found" });
    }

    return reply(200, { success: true, share: result.rows[0] });
  } catch (err) {
    console.error("accept_profile_share_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
