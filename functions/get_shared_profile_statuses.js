const db = require("./services/db");
const { clean, ensureSchema, parseBody, reply, verifyUserSession } = require("./services/profile-share-sync");

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureSchema();
    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    const result = await db.query(
      `SELECT id, profile_id, profile_name, status, revoked_at
       FROM profile_share_links
       WHERE recipient_user_id=$1
       ORDER BY created_at DESC`,
      [userId]
    );
    return reply(200, {
      success: true,
      relationships: result.rows.map((row) => ({
        shareId: row.id,
        profileId: row.profile_id,
        profileName: row.profile_name,
        status: row.revoked_at ? "revoked" : row.status,
        revokedAt: row.revoked_at,
      })),
    });
  } catch (err) {
    console.error("get_shared_profile_statuses error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
