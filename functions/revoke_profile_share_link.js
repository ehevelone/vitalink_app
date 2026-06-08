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
    const shareId = clean(body.shareId || body.share_id);

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!shareId) {
      return reply(400, { success: false, error: "Missing share id" });
    }

    const result = await db.query(
      `
      UPDATE profile_share_links
      SET status = 'revoked',
          revoked_at = NOW()
      WHERE id = $1
        AND owner_user_id = $2
        AND revoked_at IS NULL
      RETURNING id
      `,
      [shareId, userId]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "Share link not found" });
    }

    await db.query(
      `
      DELETE FROM profile_update_recipients
      WHERE share_link_id = $1
        AND status = 'pending'
      `,
      [shareId]
    );

    return reply(200, { success: true });
  } catch (err) {
    console.error("revoke_profile_share_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
