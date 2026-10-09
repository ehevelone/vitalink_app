const db = require("./db");
const { schemaOnce } = require("./schema-once");
const admin = require("firebase-admin");
const { ensureAgentDevicesSchema } = require("./agent-devices");
const {
  deviceLanguage,
  ensureLanguageColumns,
  sendLocalizedMulticast,
} = require("./notification-language");

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

// title and body may be strings or (language) => string, so each phone
// gets the text in its own app language.
async function sendReferralPush({ recipient, referral, title, body }) {
  if (!recipient || !recipient.id || !initFirebase()) {
    console.log("Referral push skipped", {
      reason: !recipient || !recipient.id ? "missing_recipient" : "firebase_not_configured",
      recipientType: recipient?.type || null,
      recipientId: recipient?.id || null,
      referralId: referral?.id || null,
    });

    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  let devices;
  if (recipient.type === "agent") {
    await ensureAgentDevicesSchema();
    devices = await db.query(
      `SELECT id, device_token, app_language
       FROM agent_devices
       WHERE agent_id = $1
         AND device_token IS NOT NULL
         AND TRIM(device_token) <> ''
         AND TRIM(device_token) <> 'NO_TOKEN'`,
      [recipient.id]
    );
  } else {
    await ensureLanguageColumns();
    devices = await db.query(
      `SELECT id, device_token, app_language
       FROM user_devices
       WHERE user_id = $1
         AND device_token IS NOT NULL
         AND TRIM(device_token) <> ''
         AND TRIM(device_token) <> 'NO_TOKEN'`,
      [recipient.id]
    );
  }

  const seen = new Set();
  const targets = [];

  for (const row of devices.rows) {
    const token = clean(row.device_token);
    if (!token || seen.has(token)) continue;
    seen.add(token);
    targets.push({ id: row.id, token, language: deviceLanguage(row) });
  }

  if (!targets.length) {
    console.log("Referral push skipped", {
      reason: "no_device_tokens",
      recipientType: recipient.type,
      recipientId: recipient.id,
      referralId: referral?.id || null,
    });

    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  console.log("Referral push sending", {
    recipientType: recipient.type,
    recipientId: recipient.id,
    referralId: referral?.id || null,
    devicesTargeted: targets.length,
    targetRows: targets.map((item) => item.id),
    tokenTails: targets.map((item) => item.token.slice(-8)),
  });

  const textFor = (value, language) => (typeof value === "function" ? value(language) : value);
  const response = await sendLocalizedMulticast(admin.messaging(), targets, (language, tokens) => ({
    tokens,
    notification: {
      title: textFor(title, language),
      body: textFor(body, language),
    },
    android: {
      priority: "high",
      notification: {
        channelId: "vitalink_high_importance",
        priority: "high",
        defaultSound: true,
      },
    },
    data: {
      click_action: "FLUTTER_NOTIFICATION_CLICK",
      route: recipient.type === "agent" ? "/agent_referrals" : "/referral_center",
      type: "agent_referral",
      referralId: referral.id,
      title: textFor(title, language),
      body: textFor(body, language),
    },
  }));

  const errors = (response.responses || [])
    .filter((item) => !item.success)
    .map((item) => item.error?.code || item.error?.message || "unknown");

  const results = response.responses || [];
  for (let i = 0; i < targets.length; i += 1) {
    const result = results[i];
    if (!result) continue;

    const deviceTable = recipient.type === "agent"
      ? "agent_devices"
      : "user_devices";
    await db.query(
      `
      UPDATE ${deviceTable}
      SET push_status = $1,
          last_push_at = NOW(),
          last_push_success_at = CASE WHEN $2 THEN NOW() ELSE last_push_success_at END,
          last_push_failure_at = CASE WHEN $2 THEN last_push_failure_at ELSE NOW() END,
          last_push_error = $3,
          updated_at = NOW()
      WHERE id = $4
      `,
      [
        result.success ? "delivered" : "failed",
        result.success,
        result.success ? null : (result.error?.code || result.error?.message || "Push failed"),
        targets[i].id,
      ]
    );
  }

  console.log("Referral push result", {
    recipientType: recipient.type,
    recipientId: recipient.id,
    referralId: referral?.id || null,
    devicesTargeted: targets.length,
    targetRows: targets.map((item) => item.id),
    tokenTails: targets.map((item) => item.token.slice(-8)),
    successCount: response.successCount,
    failureCount: response.failureCount,
    errors,
  });

  return {
    devicesTargeted: targets.length,
    successCount: response.successCount,
    failureCount: response.failureCount,
    errors,
  };
}

// Schema setup runs once per warm instance (see schema-once.js).
ensureReferralSchema = schemaOnce("referral-center:ensureReferralSchema", ensureReferralSchema);

module.exports = {
  clean,
  ensureReferralSchema,
  reply,
  sendReferralPush,
  verifyUserSession,
};
