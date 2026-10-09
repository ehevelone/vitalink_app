// Admin-only broadcast: tell every registered phone (clients and agents) that
// a new VitaLink version is available. Uses a visible notification payload so
// the phone's system shows it even on old app versions and when the app is
// closed; the app opens /update_app when it is tapped.
const db = require("./services/db");
const { requireAdmin } = require("./_adminAuth");
const { schemaOnce } = require("./services/schema-once");
const { ensureAgentDevicesSchema } = require("./services/agent-devices");
const {
  deviceLanguage,
  ensureLanguageColumns,
} = require("./services/notification-language");

const BATCH_SIZE = 500; // FCM multicast limit
const COOLDOWN_MINUTES = 10;
const DEFAULT_TITLE = "VitaLink Update Available";
const DEFAULT_BODY =
  "A new version of VitaLink is ready. Please open the Google Play Store or " +
  "App Store and update VitaLink to keep your account and emergency " +
  "information working.";
// Phones set to Spanish get the Spanish text (titleEs/bodyEs from the admin
// page, or these defaults).
const DEFAULT_TITLE_ES = "Hay una actualización de VitaLink disponible";
const DEFAULT_BODY_ES =
  "Hay una versión nueva de VitaLink. Abra Google Play Store o App Store y " +
  "actualice VitaLink para que su cuenta y su información de emergencia " +
  "sigan funcionando.";

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });

const ensureBroadcastTable = schemaOnce("send_app_update_notification:table", () =>
  db.query(`
    CREATE TABLE IF NOT EXISTS app_update_broadcasts (
      id BIGSERIAL PRIMARY KEY,
      admin_id TEXT,
      platform TEXT NOT NULL,
      devices_targeted INTEGER NOT NULL,
      success_count INTEGER NOT NULL,
      failure_count INTEGER NOT NULL,
      sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `)
);

function messaging() {
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
  return admin.messaging();
}

function isInvalidTokenError(err) {
  const text = `${err?.code || ""} ${err?.message || ""}`.toLowerCase();
  return (
    text.includes("registration-token-not-registered") ||
    text.includes("requested entity was not found") ||
    text.includes("invalid-registration-token")
  );
}

function cleanText(value, fallback, maxLength) {
  const text = String(value || "").trim();
  return text ? text.slice(0, maxLength) : fallback;
}

async function collectTargets(platform) {
  const platformFilter = platform === "all" ? "" : "AND LOWER(COALESCE(platform,''))=$1";
  const params = platform === "all" ? [] : [platform];
  const tokenFilter = `device_token IS NOT NULL
    AND TRIM(device_token) <> ''
    AND TRIM(device_token) <> 'NO_TOKEN'`;

  const users = await db.query(
    `SELECT id, device_token, app_language FROM user_devices
     WHERE device_status='active' AND ${tokenFilter} ${platformFilter}`,
    params
  );
  let agents = { rows: [] };
  try {
    agents = await db.query(
      `SELECT id, device_token, app_language FROM agent_devices
       WHERE ${tokenFilter} ${platformFilter}`,
      params
    );
  } catch (err) {
    // agent_devices is created on first agent registration; none yet is fine.
    if (err.code !== "42P01") throw err;
  }

  const byToken = new Map();
  for (const row of users.rows) {
    byToken.set(row.device_token.trim(), {
      table: "user_devices",
      id: row.id,
      language: deviceLanguage(row),
    });
  }
  for (const row of agents.rows) {
    const token = row.device_token.trim();
    if (!byToken.has(token)) {
      byToken.set(token, { table: "agent_devices", id: row.id, language: deviceLanguage(row) });
    }
  }
  return [...byToken.entries()].map(([token, owner]) => ({ token, ...owner }));
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });

    const auth = await requireAdmin(event);
    if (auth.error) return reply(401, { success: false, error: "Unauthorized" });

    const body = JSON.parse(event.body || "{}");
    const platform = ["android", "ios"].includes(body.platform) ? body.platform : "all";
    const title = cleanText(body.title, DEFAULT_TITLE, 60);
    const text = cleanText(body.body, DEFAULT_BODY, 240);
    const titleEs = cleanText(body.titleEs, DEFAULT_TITLE_ES, 60);
    const textEs = cleanText(body.bodyEs, DEFAULT_BODY_ES, 240);
    await ensureAgentDevicesSchema();
    await ensureLanguageColumns();
    const targets = await collectTargets(platform);

    // Preview: how many phones would be notified, without sending.
    if (body.dryRun === true) {
      return reply(200, {
        success: true,
        dryRun: true,
        platform,
        devicesTargeted: targets.length,
        spanishDevices: targets.filter((target) => target.language === "es").length,
      });
    }

    await ensureBroadcastTable();
    if (body.force !== true) {
      const recent = await db.query(
        `SELECT sent_at FROM app_update_broadcasts
         WHERE sent_at > NOW() - ($1 || ' minutes')::interval
         ORDER BY sent_at DESC LIMIT 1`,
        [String(COOLDOWN_MINUTES)]
      );
      if (recent.rows.length) {
        return reply(429, {
          success: false,
          error: `An update notification was already sent in the last ${COOLDOWN_MINUTES} minutes.`,
        });
      }
    }

    let successCount = 0;
    let failureCount = 0;
    const invalid = [];
    const fcm = targets.length ? messaging() : null;

    const groups = [
      { language: "en", title, text, list: targets.filter((t) => t.language !== "es") },
      { language: "es", title: titleEs, text: textEs, list: targets.filter((t) => t.language === "es") },
    ];
    for (const group of groups) {
      for (let start = 0; start < group.list.length; start += BATCH_SIZE) {
        const batch = group.list.slice(start, start + BATCH_SIZE);
        const response = await fcm.sendEachForMulticast({
          tokens: batch.map((target) => target.token),
          notification: { title: group.title, body: group.text },
          data: { type: "app_update", route: "/update_app", title: group.title, body: group.text },
          android: {
            priority: "high",
            notification: { channelId: "vitalink_high_importance" },
          },
          apns: { payload: { aps: { sound: "default" } } },
        });
        successCount += response.successCount || 0;
        failureCount += response.failureCount || 0;
        (response.responses || []).forEach((result, index) => {
          if (!result.success && isInvalidTokenError(result.error)) invalid.push(batch[index]);
        });
      }
    }

    // Stop sending to phones that uninstalled the app.
    for (const target of invalid) {
      if (target.table === "agent_devices") {
        await db.query("DELETE FROM agent_devices WHERE id=$1", [target.id]);
      } else {
        await db.query("UPDATE user_devices SET device_token='NO_TOKEN', updated_at=NOW() WHERE id=$1", [target.id]);
      }
    }

    await db.query(
      `INSERT INTO app_update_broadcasts
        (admin_id, platform, devices_targeted, success_count, failure_count)
       VALUES ($1,$2,$3,$4,$5)`,
      [String(auth.admin?.id ?? ""), platform, targets.length, successCount, failureCount]
    );

    return reply(200, {
      success: true,
      platform,
      devicesTargeted: targets.length,
      successCount,
      failureCount,
      uninstalledRemoved: invalid.length,
    });
  } catch (err) {
    console.error("send_app_update_notification error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
