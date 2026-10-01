const db = require("./services/db");
const {
  cleanupExpiredPackages,
  ensureSchema,
  parseBody,
  reply,
  verifyUserSession,
  clean,
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

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const result = await db.query(
      `
      SELECT
        pur.id AS recipient_package_id,
        pur.status AS recipient_status,
        pur.share_link_id,
        pup.id AS package_id,
        pup.profile_id,
        pup.profile_name,
        pup.allowed_sections,
        pup.encrypted_payload,
        pup.created_at,
        pup.expires_at
      FROM profile_update_recipients pur
      JOIN profile_update_packages pup ON pup.id = pur.package_id
      WHERE pur.recipient_user_id = $1
        AND pur.status = 'pending'
        AND pup.expires_at > NOW()
      ORDER BY pup.created_at DESC
      `,
      [userId]
    );

    const packages = result.rows.map((row) => ({
        recipientPackageId: row.recipient_package_id,
        packageId: row.package_id,
        shareId: row.share_link_id,
        profileId: row.profile_id,
        profileName: row.profile_name,
        allowedSections: row.allowed_sections,
        createdAt: row.created_at,
        expiresAt: row.expires_at,
        encryptedPayload: row.encrypted_payload,
      }));

    return reply(200, { success: true, packages });
  } catch (err) {
    console.error("get_profile_update_packages error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
