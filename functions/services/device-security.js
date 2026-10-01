const db = require("./db");

async function ensureDeviceSecuritySchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS user_devices (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      agent_id INTEGER REFERENCES agents(id) ON DELETE CASCADE,
      device_id TEXT,
      device_token TEXT,
      platform TEXT,
      created_at TIMESTAMPTZ DEFAULT NOW(),
      updated_at TIMESTAMPTZ DEFAULT NOW()
    )
  `);
  await db.query(`ALTER TABLE user_devices DROP CONSTRAINT IF EXISTS user_devices_user_id_unique`);
  await db.query(`
    ALTER TABLE user_devices
    ADD COLUMN IF NOT EXISTS device_status TEXT NOT NULL DEFAULT 'active',
    ADD COLUMN IF NOT EXISTS device_label TEXT,
    ADD COLUMN IF NOT EXISTS push_status TEXT,
    ADD COLUMN IF NOT EXISTS last_push_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_success_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_failure_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS last_push_error TEXT,
    ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS revoked_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS revocation_reason TEXT
  `);
  await db.query(`
    CREATE UNIQUE INDEX IF NOT EXISTS idx_user_devices_user_device_id
    ON user_devices(user_id, device_id)
    WHERE user_id IS NOT NULL AND device_id IS NOT NULL
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS device_security_events (
      id BIGSERIAL PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      device_id TEXT,
      event_type TEXT NOT NULL,
      reason TEXT,
      platform TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function recordDeviceEvent(userId, deviceId, eventType, reason, platform) {
  await db.query(
    `INSERT INTO device_security_events (user_id, device_id, event_type, reason, platform)
     VALUES ($1,$2,$3,$4,$5)`,
    [userId, deviceId || null, eventType, reason || null, platform || null]
  );
}

async function notifyRevokedDevices(rows, reason) {
  const tokens = rows
    .map((row) => String(row.device_token || "").trim())
    .filter((token) => token && token !== "NO_TOKEN");
  if (!tokens.length) return;

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
    await admin.messaging().sendEachForMulticast({
      tokens,
      data: {
        type: "device_revoked",
        reason: reason || "replaced",
        title: reason === "replaced"
          ? "VitaLink moved to a new device"
          : "VitaLink device disabled",
        body: reason === "replaced"
          ? "This old device has been disabled. Its local VitaLink profiles were not erased."
          : "This lost or stolen device has been disabled and its local VitaLink profiles will be erased.",
      },
      android: { priority: "high" },
      apns: { headers: { "apns-priority": "10" }, payload: { aps: { "content-available": 1 } } },
    });
  } catch (err) {
    console.error("Device revocation push failed:", err.message);
  }
}

module.exports = { ensureDeviceSecuritySchema, recordDeviceEvent, notifyRevokedDevices };
