const db = require("./db");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const reply = (statusCode, body) => ({
  statusCode,
  headers,
  body: JSON.stringify(body),
});

function parseBody(event) {
  return event.isBase64Encoded
    ? JSON.parse(Buffer.from(event.body || "", "base64").toString("utf8") || "{}")
    : JSON.parse(event.body || "{}");
}

function clean(value) {
  const text = String(value ?? "").trim();
  return text || null;
}

function normalizeCode(value) {
  return String(value || "")
    .replace(/[\u2010-\u2015\u2212]/g, "-")
    .replace(/[^A-Za-z0-9-]/g, "")
    .trim()
    .toUpperCase();
}

async function ensureSchema({ cleanup = true } = {}) {
  await db.query(`
    CREATE TABLE IF NOT EXISTS device_transfer_packages (
      id UUID PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      transfer_code TEXT UNIQUE NOT NULL,
      encrypted_payload TEXT,
      chunk_count INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      downloaded_at TIMESTAMPTZ,
      redeemed_device_id TEXT,
      expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '6 hours'
    )
  `);
  await db.query(`
    ALTER TABLE device_transfer_packages
    ALTER COLUMN encrypted_payload DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS chunk_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS redeemed_device_id TEXT
  `);
  await db.query(`
    CREATE TABLE IF NOT EXISTS device_transfer_chunks (
      transfer_id UUID NOT NULL REFERENCES device_transfer_packages(id) ON DELETE CASCADE,
      chunk_index INTEGER NOT NULL,
      chunk_data TEXT NOT NULL,
      PRIMARY KEY (transfer_id, chunk_index)
    )
  `);
  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_device_transfer_user_status
    ON device_transfer_packages (user_id, status, expires_at)
  `);
  return cleanup ? cleanupExpiredTransfers() : 0;
}

async function verifyActiveUserDevice(userId, deviceId) {
  if (!userId || !deviceId) return false;
  const result = await db.query(
    `SELECT 1 FROM user_devices
     WHERE user_id=$1 AND device_id=$2 AND device_status='active'
     LIMIT 1`,
    [userId, deviceId]
  );
  return result.rows.length > 0;
}

async function cleanupExpiredTransfers() {
  const result = await db.query(
    `DELETE FROM device_transfer_packages
     WHERE expires_at <= NOW()`
  );
  return result.rowCount || 0;
}

module.exports = {
  clean,
  cleanupExpiredTransfers,
  db,
  ensureSchema,
  normalizeCode,
  parseBody,
  reply,
  verifyActiveUserDevice,
};
