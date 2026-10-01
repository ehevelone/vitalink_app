const db = require("./services/db");
const {
  clean,
  ensureSchema,
  parseBody,
  reply,
  verifyUserSession,
} = require("./services/profile-share-sync");

async function notifyRecipient(recipientUserId, shareId) {
  if (!recipientUserId) return;
  try {
    const admin = require("firebase-admin");
    if (!admin.apps.length) {
      let privateKey = process.env.FIREBASE_PRIVATE_KEY || "";
      if (privateKey.includes("\\n")) privateKey = privateKey.replace(/\\n/g, "\n");
      admin.initializeApp({
        credential: admin.credential.cert({
          projectId: process.env.FIREBASE_PROJECT_ID,
          clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
          privateKey,
        }),
      });
    }
    const devices = await db.query(
      `SELECT device_token FROM user_devices
       WHERE user_id=$1 AND device_status='active' AND device_token IS NOT NULL`,
      [recipientUserId]
    );
    const tokens = devices.rows.map((row) => row.device_token).filter(Boolean);
    if (tokens.length) {
      await admin.messaging().sendEachForMulticast({
        tokens,
        data: {
          type: "profile_share_revoked",
          shareId: String(shareId),
          title: "Profile sharing ended",
          body: "A shared VitaLink profile is no longer receiving updates.",
        },
        android: { priority: "high" },
        apns: { payload: { aps: { "content-available": 1 } } },
      });
    }
  } catch (err) {
    console.error("Profile revocation push failed:", err.message);
  }
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
      RETURNING id, recipient_user_id
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

    await notifyRecipient(result.rows[0].recipient_user_id, shareId);

    return reply(200, { success: true });
  } catch (err) {
    console.error("revoke_profile_share_link error:", err);
    return reply(500, { success: false, error: err.message || "Server error" });
  }
};
