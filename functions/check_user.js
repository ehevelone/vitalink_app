const db = require("./services/db");
const crypto = require("crypto");
const { hashPassword, verifyPassword } = require("./services/passwords");
const { ensureAccountAccessSchema } = require("./services/account-access");
const { ensureUserSessionColumns } = require("./services/user-auth");
const {
  ensureDeviceSecuritySchema,
  recordDeviceEvent,
  notifyRevokedDevices,
} = require("./services/device-security");
const {
  ensureSchema: ensureDeviceTransferSchema,
  normalizeCode: normalizeTransferCode,
} = require("./services/device-transfer");
const { requestLanguage } = require("./services/notification-language");

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

async function createUserSession(userId) {
  const token = crypto.randomBytes(32).toString("hex");
  const expires = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);
  await db.query(`UPDATE users SET session_token=$1, session_expires=$2 WHERE id=$3`, [token, expires, userId]);
  return token;
}

exports.handler = async (event) => {
  const startedAt = Date.now();
  const logStage = (stage, details = {}) => console.info("USER_LOGIN_STAGE", {
    stage,
    elapsedMs: Date.now() - startedAt,
    ...details,
  });
  try {
    if (event.httpMethod === "OPTIONS") return { statusCode: 200, headers, body: "" };
    if (event.httpMethod !== "POST") return reply(false, { error: "Method Not Allowed" }, 405);

    logStage("LOGIN_START");

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
    logStage("AUTHENTICATION_COMPLETE");
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
      activeDevices.rows.length
    ) {
      return reply(false, {
        error: "INSTALLATION_RECOVERY_NOT_VERIFIED",
        message: "This installation could not be verified as the current phone. Use a transfer code, or choose Lost or Stolen if the old phone is unavailable.",
      }, 409);
    }

    if (activeDevices.rows.length && replace !== true) {
      logStage("DEVICE_CONFLICT_DETECTED");
      return reply(false, {
        error: "DEVICE_ACTIVE",
        activeDevice: {
          platform: activeDevices.rows[0].platform,
          lastSeenAt: activeDevices.rows[0].last_seen_at || activeDevices.rows[0].updated_at,
        },
      }, 403);
    }

    if (activeDevices.rows.length && replace === true) {
      logStage("DEVICE_SWITCH_REQUEST_START", { replacementReason });
      if (replacementReason === "replaced") {
        await ensureDeviceTransferSchema();
        // Current apps send the code first so a typo or expired code is caught
        // before the old phone is disabled. Older apps send no code and keep
        // the previous "any finished package" check.
        const transferCode = normalizeTransferCode(body.transfer_code);
        const transfer = await db.query(
          `SELECT p.id
           FROM device_transfer_packages p
           WHERE p.user_id=$1 AND p.status='pending' AND p.expires_at>NOW()
             AND ($2::text IS NULL OR p.transfer_code=$2)
             AND p.chunk_count>0
             AND p.chunk_count=(
               SELECT COUNT(*)::INTEGER
               FROM device_transfer_chunks c
               WHERE c.transfer_id=p.id
             )
           ORDER BY p.created_at DESC
           LIMIT 1`,
          [user.id, transferCode || null]
        );
        if (!transfer.rows.length && transferCode) {
          return reply(false, {
            error: "TRANSFER_CODE_INVALID",
            message: "That transfer code doesn't match. Check the code on your old phone and try again.",
          }, 409);
        }
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
      logStage("DEVICE_SWITCH_DATABASE_COMPLETE", {
        revokedDeviceCount: activeDevices.rows.length,
      });
      for (const oldDevice of activeDevices.rows) {
        await recordDeviceEvent(
          user.id,
          oldDevice.device_id,
          replacementReason === "replaced" ? "device_replaced" : "device_revoked",
          replacementReason,
          oldDevice.platform
        );
      }
      logStage("DEVICE_REVOCATION_PUSH_START");
      await notifyRevokedDevices(activeDevices.rows, replacementReason);
      logStage("DEVICE_REVOCATION_PUSH_COMPLETE");
    }

    if (fcmToken) {
      await db.query(
        `UPDATE user_devices
         SET device_token=NULL, updated_at=NOW()
         WHERE device_token=$1
           AND NOT (user_id=$2 AND device_id=$3)`,
        [fcmToken, user.id, deviceId]
      );
    }

    await db.query(
      `INSERT INTO user_devices
        (user_id, agent_id, device_id, device_token, platform, device_status, last_seen_at, created_at, updated_at, app_language)
       VALUES ($1,$2,$3,$4,$5,'active',NOW(),NOW(),NOW(),$6)
       ON CONFLICT (user_id, device_id) WHERE user_id IS NOT NULL AND device_id IS NOT NULL
       DO UPDATE SET agent_id=NULL,
         device_token=COALESCE(EXCLUDED.device_token,user_devices.device_token),
         platform=EXCLUDED.platform,
         device_status='active', revoked_at=NULL, revocation_reason=NULL,
         app_language=COALESCE(EXCLUDED.app_language, user_devices.app_language),
         last_seen_at=NOW(), updated_at=NOW()`,
      [user.id, null, deviceId, fcmToken || null, platform || "unknown", requestLanguage(event, body)]
    );
    await recordDeviceEvent(user.id, deviceId, replace === true ? "replacement_activated" : "login", replacementReason, platform);
    logStage("DEVICE_ACTIVATION_COMPLETE");

    const sessionToken = await createUserSession(user.id);
    logStage("SESSION_CREATED");
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
