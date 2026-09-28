const crypto = require("crypto");
const db = require("./services/db");
const {
  clean,
  ensureSchema,
  parseBody,
  reply,
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

    const client = await db.connect();
    let committed = false;
    let share;
    const readyPackages = [];
    try {
      await client.query("BEGIN");
      const result = await client.query(
        `
        UPDATE profile_share_links
        SET recipient_user_id = $1,
            status = 'accepted',
            accepted_at = COALESCE(accepted_at, NOW())
        WHERE invite_code = $2
          AND status <> 'revoked'
          AND revoked_at IS NULL
          AND (recipient_user_id IS NULL OR recipient_user_id = $1)
        RETURNING *
        `,
        [userId, inviteCode]
      );

      if (!result.rows.length) {
        await client.query("ROLLBACK");
        return reply(404, { success: false, error: "Share invite not found" });
      }

      share = result.rows[0];
      const staged = await client.query(
        `
        SELECT id, profile_name
        FROM profile_update_packages
        WHERE pending_share_link_id = $1
          AND expires_at > NOW()
        FOR UPDATE
        `,
        [share.id]
      );

      for (const item of staged.rows) {
        await client.query(
          `
          INSERT INTO profile_update_recipients (
            id, package_id, recipient_user_id, share_link_id
          ) VALUES ($1,$2,$3,$4)
          `,
          [crypto.randomUUID(), item.id, userId, share.id]
        );
        await client.query(
          `UPDATE profile_update_packages SET pending_share_link_id = NULL WHERE id = $1`,
          [item.id]
        );
        readyPackages.push(item);
      }

      await client.query("COMMIT");
      committed = true;
    } catch (error) {
      if (!committed) await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }

    for (const item of readyPackages) {
      try {
        await sendProfileUpdatePush({
          recipientUserIds: [userId],
          packageId: item.id,
          profileName: item.profile_name,
        });
      } catch (error) {
        console.error("Profile update notification failed:", error);
      }
    }

    return reply(200, {
      success: true,
      share,
      updatesReady: readyPackages.length,
    });
  } catch (err) {
    console.error("accept_profile_share_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
