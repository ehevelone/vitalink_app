const admin = require("firebase-admin");
const db = require("./services/db");
const {
  clean,
  ensureSchema,
  parseBody,
  reply,
  uniqueTargets,
  verifyUserSession,
} = require("./services/profile-share-sync");
const {
  ensureLanguageColumns,
  notificationText,
  sendLocalizedMulticast,
} = require("./services/notification-language");

function initFirebase() {
  if (admin.apps.length) return true;
  let privateKey = process.env.FIREBASE_PRIVATE_KEY || "";
  if (!process.env.FIREBASE_PROJECT_ID || !process.env.FIREBASE_CLIENT_EMAIL || !privateKey) {
    return false;
  }
  if (privateKey.includes("\\n")) privateKey = privateKey.replace(/\\n/g, "\n");
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey,
    }),
  });
  return true;
}

async function notifyOwner(ownerUserId, profileName) {
  if (!ownerUserId || !initFirebase()) return;
  await ensureLanguageColumns();
  const devices = await db.query(
    `SELECT device_token, app_language FROM user_devices
     WHERE user_id::TEXT=$1 AND device_status='active'
       AND device_token IS NOT NULL AND TRIM(device_token) <> ''`,
    [String(ownerUserId)]
  );
  const targets = uniqueTargets(devices.rows);
  if (!targets.length) return;
  await sendLocalizedMulticast(admin.messaging(), targets, (language, tokens) => ({
    tokens,
    notification: {
      title: notificationText("sharedRemovedTitle", language),
      body: notificationText("sharedRemovedBody", language, { profile: profileName }),
    },
    data: { type: "profile_share_recipient_removed" },
  }));
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    await ensureSchema();
    const body = parseBody(event);
    const userId = clean(body.userId || body.user_id);
    const shareId = clean(body.shareId || body.share_id);
    if (!(await verifyUserSession(userId, clean(body.sessionToken)))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }
    if (!shareId) return reply(400, { success: false, error: "Missing share id" });

    const result = await db.query(
      `UPDATE profile_share_links
       SET status='recipient_removed', recipient_removed_at=NOW()
       WHERE id=$1 AND recipient_user_id=$2 AND status <> 'revoked'
       RETURNING owner_user_id, profile_name`,
      [shareId, userId]
    );
    if (!result.rows.length) {
      return reply(404, { success: false, error: "Shared profile not found" });
    }
    await db.query(
      `DELETE FROM profile_update_recipients
       WHERE share_link_id=$1 AND status='pending'`,
      [shareId]
    );
    await notifyOwner(result.rows[0].owner_user_id, result.rows[0].profile_name);
    return reply(200, { success: true });
  } catch (err) {
    console.error("remove_shared_profile_copy error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
