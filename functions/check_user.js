const db = require("./services/db");
const crypto = require("crypto");
const { hashPassword, verifyPassword } = require("./services/passwords");
const { ensureAccountAccessSchema } = require("./services/account-access");
const {
  ensureDeviceSecuritySchema,
  recordDeviceEvent,
  notifyRevokedDevices,
} = require("./services/device-security");
const { ensureSchema: ensureDeviceTransferSchema } = require("./services/device-transfer");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (success, obj = {}, code = 200) => ({
  statusCode: code,
  headers,
  body: JSON.stringify({ success, ...obj }),
});

async function ensureUserSessionColumns() {
  await db.query(`ALTER TABLE users ADD COLUMN IF NOT EXISTS session_token TEXT, ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ`);
}

async function createUserSession(userId) {
  const token = crypto.randomBytes(32).toString("hex");
  const expires = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);
  await db.query(`UPDATE users SET session_token=$1, session_expires=$2 WHERE id=$3`, [token, expires, userId]);
  return token;
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return { statusCode: 200, headers, body: "" };
    if (event.httpMethod !== "POST") return reply(false, { error: "Method Not Allowed" }, 405);

    await ensureUserSessionColumns();
    await ensureAccountAccessSchema();
    await ensureDeviceSecuritySchema();

    const body = JSON.parse(event.body || "{}");
    const { email, password, device_id: deviceId, replace, platform } = body;
    const fcmToken = String(body.fcm_token || body.deviceToken || "").trim();
    const recoverInstallation = body.recover_installation === true;
    const replacementReason = ["lost", "stolen", "replaced"].includes(body.replacement_reason)
      ? body.replacement_reason
      : "replaced";

    if (!email || !password || !deviceId) {
      return reply(false, { error: "Email, password, and device are required" }, 400);
    }

    const result = await db.query(
      `SELECT id, email, password_hash, first_name, last_name, agent_id,
              access_sponsor, relationship_status, messaging_consent_status
       FROM users WHERE LOWER(email)=LOWER($1) LIMIT 1`,
      [email.trim()]
    );
    if (!result.rows.length) return reply(false, { error: "User not found" }, 404);

    const user = result.rows[0];
    const passwordCheck = await verifyPassword(password, user.password_hash);
    if (!passwordCheck.valid) return reply(false, { error: "Invalid password" }, 401);
    if (passwordCheck.legacy) {
      await db.query("UPDATE users SET password_hash=$1 WHERE id=$2", [await hashPassword(password), user.id]);
    }

    if (fcmToken) {
      try {
        const matchingInstallation = await db.query(
          `SELECT id, device_id
           FROM user_devices
           WHERE user_id=$1 AND device_token=$2 AND device_status='active'
           ORDER BY updated_at DESC
           LIMIT 1`,
          [user.id, fcmToken]
        );

        if (
          matchingInstallation.rows.length &&
          matchingInstallation.rows[0].device_id !== deviceId
        ) {
          await db.query(
            `UPDATE user_devices
             SET device_id=NULL, device_token=NULL, device_status='replaced',
               revoked_at=NOW(), revocation_reason='installation_id_merged', updated_at=NOW()
             WHERE user_id=$1 AND device_id=$2 AND id<>$3`,
            [user.id, deviceId, matchingInstallation.rows[0].id]
          );
          await db.query(
            `UPDATE user_devices
             SET device_id=$1, last_seen_at=NOW(), updated_at=NOW()
             WHERE id=$2`,
            [deviceId, matchingInstallation.rows[0].id]
          );
          await recordDeviceEvent(
            user.id,
            deviceId,
            "installation_id_recovered",
            "matching_notification_token",
            platform
          );
        }
      } catch (_) {
        // Identity repair is opportunistic. Continue to the normal recovery
        // flow without logging device identifiers or notification tokens.
        console.error("Installation identity repair failed");
      }
    }

    const sameDevice = await db.query(
      `SELECT * FROM user_devices WHERE user_id=$1 AND device_id=$2 LIMIT 1`,
      [user.id, deviceId]
    );
    if (sameDevice.rows.length && sameDevice.rows[0].device_status !== "active") {
      return reply(false, { error: "DEVICE_REVOKED", reason: sameDevice.rows[0].revocation_reason }, 403);
    }

    const activeDevices = await db.query(
      `SELECT * FROM user_devices
       WHERE user_id=$1 AND device_status='active' AND COALESCE(device_id,'')<>$2
       ORDER BY updated_at DESC`,
      [user.id, deviceId]
    );

    if (
      recoverInstallation &&
      !sameDevice.rows.length &&
      activeDevices.rows.length
    ) {
      const currentRecord = activeDevices.rows[0];
      await db.query(
        `UPDATE user_devices
         SET device_status='replaced', device_token=NULL, revoked_at=NOW(),
           revocation_reason='installation_id_merged', updated_at=NOW()
         WHERE user_id=$1 AND device_status='active' AND id<>$2`,
        [user.id, currentRecord.id]
      );
      await db.query(
        `UPDATE user_devices
         SET device_id=$1, device_token=COALESCE($2,device_token),
           platform=$3, last_seen_at=NOW(), updated_at=NOW()
         WHERE id=$4 AND user_id=$5 AND device_status='active'`,
        [deviceId, fcmToken || null, platform || "unknown", currentRecord.id, user.id]
      );
      await recordDeviceEvent(
        user.id,
        deviceId,
        "installation_id_recovered",
        "authenticated_current_phone_confirmation",
        platform
      );
      activeDevices.rows.length = 0;
    }

    if (activeDevices.rows.length && replace !== true) {
      return reply(false, {
        error: "DEVICE_ACTIVE",
        activeDevice: {
          platform: activeDevices.rows[0].platform,
          lastSeenAt: activeDevices.rows[0].last_seen_at || activeDevices.rows[0].updated_at,
        },
      }, 403);
    }

    if (activeDevices.rows.length && replace === true) {
      if (replacementReason === "replaced") {
        await ensureDeviceTransferSchema();
        const transfer = await db.query(
          `SELECT p.id
           FROM device_transfer_packages p
           WHERE p.user_id=$1 AND p.status='pending' AND p.expires_at>NOW()
             AND p.chunk_count>0
             AND p.chunk_count=(
               SELECT COUNT(*)::INTEGER
               FROM device_transfer_chunks c
               WHERE c.transfer_id=p.id
             )
           ORDER BY p.created_at DESC
           LIMIT 1`,
          [user.id]
        );
        if (!transfer.rows.length) {
          return reply(false, {
            error: "TRANSFER_REQUIRED",
            message: "Create a transfer code on the old device before replacing it.",
          }, 409);
        }
      }
      await db.query(
        `UPDATE user_devices
         SET device_status=$1, revoked_at=NOW(), revocation_reason=$2, updated_at=NOW()
         WHERE user_id=$3 AND device_status='active' AND COALESCE(device_id,'')<>$4`,
        [replacementReason === "replaced" ? "replaced" : replacementReason, replacementReason, user.id, deviceId]
      );
      for (const oldDevice of activeDevices.rows) {
        await recordDeviceEvent(
          user.id,
          oldDevice.device_id,
          replacementReason === "replaced" ? "device_replaced" : "device_revoked",
          replacementReason,
          oldDevice.platform
        );
      }
      await notifyRevokedDevices(activeDevices.rows, replacementReason);
    }

    await db.query(
      `INSERT INTO user_devices
        (user_id, agent_id, device_id, device_token, platform, device_status, last_seen_at, created_at, updated_at)
       VALUES ($1,$2,$3,$4,$5,'active',NOW(),NOW(),NOW())
       ON CONFLICT (user_id, device_id) WHERE user_id IS NOT NULL AND device_id IS NOT NULL
       DO UPDATE SET agent_id=EXCLUDED.agent_id,
         device_token=COALESCE(EXCLUDED.device_token,user_devices.device_token),
         platform=EXCLUDED.platform,
         device_status='active', revoked_at=NULL, revocation_reason=NULL,
         last_seen_at=NOW(), updated_at=NOW()`,
      [user.id, user.agent_id || null, deviceId, fcmToken || null, platform || "unknown"]
    );
    await recordDeviceEvent(user.id, deviceId, replace === true ? "replacement_activated" : "login", replacementReason, platform);

    const sessionToken = await createUserSession(user.id);
    return reply(true, {
      user: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
        agent_id: user.agent_id,
        access_sponsor: user.access_sponsor,
        relationship_status: user.relationship_status,
        messaging_consent_status: user.messaging_consent_status,
        session_token: sessionToken,
      },
    });
  } catch (err) {
    console.error("check_user error:", err);
    return reply(false, { error: "Server error" }, 500);
  }
};
