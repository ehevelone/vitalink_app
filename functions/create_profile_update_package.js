const crypto = require("crypto");
const db = require("./services/db");
const {
  clean,
  cleanupExpiredPackages,
  ensureSchema,
  normalizeSections,
  parseBody,
  reply,
  sendProfileUpdatePush,
  verifyUserSession,
} = require("./services/profile-share-sync");

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureSchema();
    await cleanupExpiredPackages();

    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    const profileId = clean(body.profileId || body.profile_id);
    const profileName = clean(body.profileName || body.profile_name);
    const packages = Array.isArray(body.packages) ? body.packages : [];
    if (!profileId || !packages.length) {
      return reply(400, { success: false, error: "Missing encrypted profile packages" });
    }

    let recipients = 0;
    let staged = 0;
    const pushes = [];
    for (const item of packages) {
      const shareId = clean(item.shareId);
      const encryptedPayload = clean(item.encryptedPayload);
      if (!shareId || !encryptedPayload) continue;

      const share = await db.query(
        `SELECT id, recipient_user_id, allowed_sections, status
         FROM profile_share_links
         WHERE id=$1 AND owner_user_id=$2 AND profile_id=$3
           AND status IN ('pending','accepted') AND revoked_at IS NULL
         LIMIT 1`,
        [shareId, userId, profileId]
      );
      if (!share.rows.length) continue;

      const packageId = crypto.randomUUID();
      const sections = normalizeSections(item.allowedSections)
        .filter((section) => normalizeSections(share.rows[0].allowed_sections).includes(section));
      if (!sections.length) continue;

      if (share.rows[0].status === "pending") {
        await db.query(
          `DELETE FROM profile_update_packages
           WHERE share_link_id=$1 AND owner_user_id=$2 AND profile_id=$3
             AND status='pending'`,
          [shareId, userId, profileId]
        );
      }

      await db.query(
        `INSERT INTO profile_update_packages
          (id, owner_user_id, profile_id, profile_name, allowed_sections,
           encrypted_payload, share_link_id, expires_at)
         VALUES ($1,$2,$3,$4,$5::jsonb,$6,$7,NOW()+INTERVAL '7 days')`,
        [packageId, userId, profileId, profileName, JSON.stringify(sections), encryptedPayload, shareId]
      );

      if (share.rows[0].status === "pending" || !share.rows[0].recipient_user_id) {
        staged += 1;
        continue;
      }
      await db.query(
        `INSERT INTO profile_update_recipients
          (id, package_id, recipient_user_id, share_link_id)
         VALUES ($1,$2,$3,$4)
         ON CONFLICT (package_id, recipient_user_id) DO NOTHING`,
        [crypto.randomUUID(), packageId, share.rows[0].recipient_user_id, shareId]
      );
      recipients += 1;
      pushes.push(sendProfileUpdatePush({
        recipientUserIds: [share.rows[0].recipient_user_id],
        packageId,
        profileName,
      }));
    }

    await Promise.allSettled(pushes);
    return reply(200, { success: true, recipients, staged: staged > 0 });
  } catch (err) {
    console.error("create_profile_update_package error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
