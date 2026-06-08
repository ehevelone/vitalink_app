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
    const profileId = clean(body.profileId || body.profile_id);

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const values = [userId];
    const where = [
      "owner_user_id = $1",
      "revoked_at IS NULL",
      "status <> 'revoked'",
    ];

    if (profileId) {
      values.push(profileId);
      where.push(`profile_id = $${values.length}`);
    }

    const result = await db.query(
      `
      SELECT
        id,
        recipient_user_id,
        invited_email,
        invited_phone,
        profile_id,
        profile_name,
        allowed_sections,
        status,
        invite_code,
        created_at,
        accepted_at
      FROM profile_share_links
      WHERE ${where.join(" AND ")}
      ORDER BY created_at DESC
      `,
      values
    );

    return reply(200, { success: true, shares: result.rows });
  } catch (err) {
    console.error("get_profile_share_links error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
