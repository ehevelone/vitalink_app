const db = require("./db");
const admin = require("firebase-admin");

function initFirebase() {
  if (admin.apps.length) return true;

  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  const privateKey = process.env.FIREBASE_PRIVATE_KEY;

  if (!projectId || !clientEmail || !privateKey) return false;

  admin.initializeApp({
    credential: admin.credential.cert({
      projectId,
      clientEmail,
      privateKey: privateKey.replace(/\\n/g, "\n"),
    }),
  });

  return true;
}

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

function clean(value) {
  return String(value || "").trim();
}

async function ensureReferralSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS agent_referrals (
      id UUID PRIMARY KEY,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      referring_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      referral_name TEXT NOT NULL,
      referral_phone TEXT,
      referral_email TEXT,
      relationship TEXT,
      reason TEXT,
      notes TEXT,
      source TEXT NOT NULL DEFAULT 'recommend_my_agent',
      public_token TEXT UNIQUE,
      contact_preference TEXT,
      link_opened_at TIMESTAMPTZ,
      contact_preference_submitted_at TIMESTAMPTZ,
      status TEXT NOT NULL DEFAULT 'Introduction Sent',
      submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      agent_first_opened_at TIMESTAMPTZ,
      agent_first_contacted_at TIMESTAMPTZ,
      appointment_scheduled_at TIMESTAMPTZ,
      client_added_at TIMESTAMPTZ,
      closed_at TIMESTAMPTZ,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    ALTER TABLE agent_referrals
    ADD COLUMN IF NOT EXISTS public_token TEXT UNIQUE,
    ADD COLUMN IF NOT EXISTS contact_preference TEXT,
    ADD COLUMN IF NOT EXISTS link_opened_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS contact_preference_submitted_at TIMESTAMPTZ
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_agent_referrals_agent_submitted
    ON agent_referrals (agent_id, submitted_at DESC)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_agent_referrals_user_submitted
    ON agent_referrals (referring_user_id, submitted_at DESC)
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS agent_referral_invites (
      id UUID PRIMARY KEY,
      agent_id INTEGER NOT NULL REFERENCES agents(id) ON DELETE CASCADE,
      referring_user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      referral_name TEXT NOT NULL,
      referral_phone TEXT,
      referral_email TEXT,
      relationship TEXT,
      reason TEXT,
      notes TEXT,
      source TEXT NOT NULL DEFAULT 'send_introduction',
      public_token TEXT UNIQUE NOT NULL,
      opened_at TIMESTAMPTZ,
      converted_referral_id UUID REFERENCES agent_referrals(id) ON DELETE SET NULL,
      submitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_agent_referral_invites_token
    ON agent_referral_invites (public_token)
  `);
}

async function verifyUserSession(userId, token) {
  if (!userId || !token) return null;

  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);

  const result = await db.query(
    `
    SELECT id, first_name, last_name, email, phone, agent_id
    FROM users
    WHERE id = $1
      AND session_token = $2
      AND session_expires > NOW()
    LIMIT 1
    `,
    [userId, token]
  );

  return result.rows[0] || null;
}

async function sendReferralPush({ recipient, referral, title, body }) {
  if (!recipient || !recipient.id || !initFirebase()) {
    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  const filters = recipient.type === "agent"
    ? "agent_id = $1 AND user_id IS NULL"
    : "user_id = $1";

  const devices = await db.query(
    `
    SELECT device_token
    FROM user_devices
    WHERE ${filters}
      AND device_token IS NOT NULL
      AND TRIM(device_token) <> ''
      AND TRIM(device_token) <> 'NO_TOKEN'
    `,
    [recipient.id]
  );

  const tokens = [...new Set(devices.rows.map((row) => row.device_token))];
  if (!tokens.length) {
    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title,
      body,
    },
    data: {
      route: recipient.type === "agent" ? "/agent_referrals" : "/referral_center",
      type: "agent_referral",
      referralId: referral.id,
    },
  });

  return {
    devicesTargeted: tokens.length,
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

module.exports = {
  clean,
  ensureReferralSchema,
  reply,
  sendReferralPush,
  verifyUserSession,
};
