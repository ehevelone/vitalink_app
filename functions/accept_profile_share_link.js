const db = require("./services/db");
const {
  clean,
  ensureSchema,
  parseBody,
  reply,
  sendProfileShareAcceptedPush,
  sendProfileUpdatePush,
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
          accepted_at = COALESCE(accepted_at, NOW()),
          invite_code = NULL,
          expires_at = NULL
      WHERE invite_code = $2
        AND status = 'pending'
        AND revoked_at IS NULL
        AND expires_at > NOW()
        AND (recipient_user_id IS NULL OR recipient_user_id = $1)
      RETURNING *
      `,
      [userId, inviteCode]
    );

    if (!result.rows.length) {
      return reply(404, { success: false, error: "Share invite not found" });
    }

    const share = result.rows[0];
    const staged = await db.query(
      `SELECT id, profile_name
       FROM profile_update_packages
       WHERE share_link_id=$1 AND owner_user_id=$2
         AND status='pending' AND expires_at>NOW()
       ORDER BY created_at DESC`,
      [share.id, share.owner_user_id]
    );
    let updatesReady = 0;
    for (const packageRow of staged.rows) {
      const inserted = await db.query(
        `INSERT INTO profile_update_recipients
          (id, package_id, recipient_user_id, share_link_id)
         VALUES (gen_random_uuid(),$1,$2,$3)
         ON CONFLICT (package_id, recipient_user_id) DO NOTHING
         RETURNING id`,
        [packageRow.id, userId, share.id]
      );
      if (inserted.rows.length) updatesReady += 1;
    }

    await sendProfileShareAcceptedPush({
      ownerUserId: share.owner_user_id,
      profileName: share.profile_name,
    });

    if (updatesReady) {
      await sendProfileUpdatePush({
        recipientUserIds: [userId],
        packageId: staged.rows[0].id,
        profileName: share.profile_name,
      });
    }

    return reply(200, { success: true, share, updatesReady });
  } catch (err) {
    console.error("accept_profile_share_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
