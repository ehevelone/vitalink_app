const db = require("./services/db");
const {
  clean,
  cleanupExpiredPackages,
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
    await cleanupExpiredPackages();

    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);
    const packageId = clean(body.packageId || body.package_id);

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    if (!packageId) {
      return reply(400, { success: false, error: "Missing package id" });
    }

    const updated = await db.query(
      `
      UPDATE profile_update_recipients
      SET status = 'downloaded',
          downloaded_at = NOW()
      WHERE package_id = $1
        AND recipient_user_id = $2
      RETURNING package_id
      `,
      [packageId, userId]
    );

    if (!updated.rows.length) {
      return reply(404, { success: false, error: "Update package not found" });
    }

    const pending = await db.query(
      `
      SELECT COUNT(*)::int AS count
      FROM profile_update_recipients
      WHERE package_id = $1
        AND status = 'pending'
      `,
      [packageId]
    );

    const pendingCount = pending.rows[0]?.count || 0;

    if (pendingCount === 0) {
      await db.query(
        `DELETE FROM profile_update_packages WHERE id = $1`,
        [packageId]
      );
    }

    return reply(200, {
      success: true,
      deleted: pendingCount === 0,
      pendingRecipients: pendingCount,
    });
  } catch (err) {
    console.error("mark_profile_update_applied error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
