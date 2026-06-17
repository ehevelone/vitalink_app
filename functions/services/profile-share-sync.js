const crypto = require("crypto");
const admin = require("firebase-admin");
const db = require("./db");
const { encrypt, decrypt } = require("../encrypt");

const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(obj),
  };
}

function parseBody(event) {
  return event.isBase64Encoded
    ? JSON.parse(Buffer.from(event.body || "", "base64").toString("utf8") || "{}")
    : JSON.parse(event.body || "{}");
}

function clean(value) {
  const text = (value ?? "").toString().trim();
  return text || null;
}

function normalizeSections(sections) {
  const allowed = new Set([
    "emergency",
    "medications",
    "doctors",
    "insurance_cards",
    "policies",
    "appointments",
  ]);

  const selected = Array.isArray(sections)
    ? sections.map(s => clean(s)).filter(Boolean)
    : [];

  const filtered = selected.filter(section => allowed.has(section));
  return filtered.length ? [...new Set(filtered)] : ["emergency"];
}

async function verifyUserSession(userId, token) {
  if (!userId || !token) return false;

  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);

  const result = await db.query(
    `
    SELECT id
    FROM users
    WHERE id = $1
      AND session_token = $2
      AND session_expires > NOW()
    LIMIT 1
    `,
    [userId, token]
  );

  return result.rows.length > 0;
}

async function ensureSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS profile_share_links (
      id UUID PRIMARY KEY,
      owner_user_id TEXT NOT NULL,
      recipient_user_id TEXT,
      invited_email TEXT,
      invited_phone TEXT,
      profile_id UUID,
      profile_name TEXT,
      allowed_sections JSONB NOT NULL DEFAULT '["emergency"]'::jsonb,
      status TEXT NOT NULL DEFAULT 'pending',
      invite_code TEXT UNIQUE NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      accepted_at TIMESTAMPTZ,
      revoked_at TIMESTAMPTZ
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS profile_update_packages (
      id UUID PRIMARY KEY,
      owner_user_id TEXT NOT NULL,
      profile_id UUID,
      profile_name TEXT,
      allowed_sections JSONB NOT NULL DEFAULT '[]'::jsonb,
      encrypted_payload TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL DEFAULT NOW() + INTERVAL '7 days'
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS profile_update_recipients (
      id UUID PRIMARY KEY,
      package_id UUID NOT NULL REFERENCES profile_update_packages(id) ON DELETE CASCADE,
      recipient_user_id TEXT NOT NULL,
      share_link_id UUID REFERENCES profile_share_links(id) ON DELETE SET NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      notified_at TIMESTAMPTZ,
      downloaded_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    ALTER TABLE profile_share_links
    ALTER COLUMN owner_user_id TYPE TEXT USING owner_user_id::TEXT,
    ALTER COLUMN recipient_user_id TYPE TEXT USING recipient_user_id::TEXT
  `);

  await db.query(`
    ALTER TABLE profile_update_packages
    ALTER COLUMN owner_user_id TYPE TEXT USING owner_user_id::TEXT
  `);

  await db.query(`
    ALTER TABLE profile_update_recipients
    ALTER COLUMN recipient_user_id TYPE TEXT USING recipient_user_id::TEXT
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_profile_share_links_owner
    ON profile_share_links (owner_user_id, status)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_profile_share_links_recipient
    ON profile_share_links (recipient_user_id, status)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_profile_update_recipients_user
    ON profile_update_recipients (recipient_user_id, status)
  `);

  await db.query(`
    CREATE INDEX IF NOT EXISTS idx_profile_update_packages_expires
    ON profile_update_packages (expires_at)
  `);
}

async function cleanupExpiredPackages() {
  await db.query(`
    DELETE FROM profile_update_packages
    WHERE expires_at < NOW()
       OR status = 'delivered'
  `);
}

function initFirebase() {
  if (admin.apps.length) return true;

  const projectId = process.env.FIREBASE_PROJECT_ID;
  const clientEmail = process.env.FIREBASE_CLIENT_EMAIL;
  let privateKey = process.env.FIREBASE_PRIVATE_KEY;

  if (!projectId || !clientEmail || !privateKey) {
    console.warn("Firebase ENV missing; profile update package created without push.");
    return false;
  }

  if (privateKey.includes("\\n")) {
    privateKey = privateKey.replace(/\\n/g, "\n");
  }

  admin.initializeApp({
    credential: admin.credential.cert({
      projectId,
      clientEmail,
      privateKey,
    }),
  });

  return true;
}

async function sendProfileUpdatePush({ recipientUserIds, packageId, profileName }) {
  if (!recipientUserIds.length || !initFirebase()) {
    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  const devicesRes = await db.query(
    `
    SELECT id, user_id, device_token
    FROM user_devices
    WHERE user_id::TEXT = ANY($1::TEXT[])
      AND device_token IS NOT NULL
      AND TRIM(device_token) <> ''
      AND TRIM(device_token) <> 'NO_TOKEN'
    `,
    [recipientUserIds]
  );

  const seen = new Set();
  const tokens = [];

  for (const row of devicesRes.rows) {
    const token = clean(row.device_token);
    if (!token || seen.has(token)) continue;
    seen.add(token);
    tokens.push(token);
  }

  if (!tokens.length) {
    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "Profile update available",
      body: `${profileName || "A VitaLink profile"} has an update ready to apply.`,
    },
    data: {
      route: "/profile_updates",
      type: "profile_update",
      packageId,
    },
  });

  return {
    devicesTargeted: tokens.length,
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

async function sendProfileShareInvitePush({ recipientUserId, inviteCode, profileName }) {
  if (!recipientUserId || !inviteCode || !initFirebase()) {
    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  const devicesRes = await db.query(
    `
    SELECT id, user_id, device_token
    FROM user_devices
    WHERE user_id::TEXT = $1
      AND device_token IS NOT NULL
      AND TRIM(device_token) <> ''
      AND TRIM(device_token) <> 'NO_TOKEN'
    `,
    [String(recipientUserId)]
  );

  const tokens = [...new Set(
    devicesRes.rows
      .map(row => clean(row.device_token))
      .filter(Boolean)
  )];

  if (!tokens.length) {
    return { devicesTargeted: 0, successCount: 0, failureCount: 0 };
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: "Profile shared with you",
      body: `${profileName || "A VitaLink profile"} was shared with you.`,
    },
    data: {
      route: "/profile_accept",
      type: "profile_share_invite",
      inviteCode,
    },
  });

  return {
    devicesTargeted: tokens.length,
    successCount: response.successCount,
    failureCount: response.failureCount,
  };
}

function createInviteCode() {
  return `VL-${crypto.randomBytes(4).toString("hex").toUpperCase()}`;
}

module.exports = {
  clean,
  cleanupExpiredPackages,
  createInviteCode,
  decrypt,
  encrypt,
  ensureSchema,
  normalizeSections,
  parseBody,
  reply,
  sendProfileShareInvitePush,
  sendProfileUpdatePush,
  verifyUserSession,
};
