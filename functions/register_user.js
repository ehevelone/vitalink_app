// functions/register_user.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");
const { ensureAccountAccessSchema } = require("./services/account-access");
const { ensureDeviceSecuritySchema, recordDeviceEvent } = require("./services/device-security");
const {
  checkAccessCodeLimit,
  clearAccessCodeFailures,
  rateLimitScope,
  recordAccessCodeFailure,
  requestIp,
} = require("./services/access-code-rate-limit");

function reply(success, obj = {}, statusCode = 200) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success, ...obj }),
  };
}

function normalizeUsPhone(value) {
  let digits = String(value || "").replace(/\D/g, "");

  if (digits.length === 11 && digits.startsWith("1")) {
    digits = digits.slice(1);
  }

  if (digits.length === 10) {
    return `+1${digits}`;
  }

  return value || null;
}

function normalizeCode(value) {
  return String(value || "")
    .replace(/[\u2010-\u2015\u2212]/g, "-")
    .replace(/[^A-Za-z0-9-]/g, "")
    .trim()
    .toUpperCase();
}

function normalizeEmail(value) {
  return String(value || "").trim().toLowerCase();
}

function getEmailValidationError(value) {
  const email = normalizeEmail(value);
  if (!email) return "Email required";

  const emailPattern = /^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@([A-Za-z0-9-]+\.)+[A-Za-z]{2,}$/;
  if (!emailPattern.test(email) || email.includes("..") || email.startsWith(".") || email.endsWith(".")) {
    return "Enter a valid email";
  }

  const tld = email.split(".").pop();
  const commonTypos = new Set(["coim", "comm", "conm", "cmo", "ocm", "cpm", "gom"]);
  if (commonTypos.has(tld)) {
    return "Check the email ending. Did you mean .com?";
  }

  return null;
}

async function ensureUserSessionColumns() {
  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);
}

async function createUserSession(userId) {
  const token = crypto.randomBytes(32).toString("hex");
  const expires = new Date(Date.now() + 180 * 24 * 60 * 60 * 1000);

  await db.query(
    `
    UPDATE users
    SET session_token = $1,
        session_expires = $2
    WHERE id = $3
    `,
    [token, expires, userId]
  );

  return token;
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
  return {
    statusCode: 200,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: "",
  };
}

if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        body: JSON.stringify({ error: "Method Not Allowed" }),
      };
    }

    const body = JSON.parse(event.body || "{}");
    const { firstName, lastName, phone, password, platform, deviceId } = body;
    const relationshipType = body.relationshipType === "prospect" ? "prospect" : "client";
    const email = normalizeEmail(body.email);
    const promoCode = normalizeCode(body.promoCode);

    await ensureUserSessionColumns();
    await ensureAccountAccessSchema();
    await ensureDeviceSecuritySchema();
    await db.query(`ALTER TABLE activation_codes ADD COLUMN IF NOT EXISTS redeemed BOOLEAN NOT NULL DEFAULT FALSE, ADD COLUMN IF NOT EXISTS redeemed_at TIMESTAMPTZ, ADD COLUMN IF NOT EXISTS redeemed_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL`);

    if (!firstName || !lastName || !email || !password || !promoCode) {
      return reply(false, { error: "Missing required fields" });
    }

    const emailError = getEmailValidationError(email);
    if (emailError) {
      return reply(false, { error: emailError });
    }

    const codeScope = rateLimitScope("registration-code", requestIp(event));
    const codeLimit = await checkAccessCodeLimit(codeScope);
    if (!codeLimit.allowed) {
      return reply(false, {
        error: "Too many incorrect codes. Try again in 15 minutes.",
        retryAfterSeconds: codeLimit.retryAfterSeconds,
      }, 429);
    }

    // ✅ Hash password
    const password_hash = await bcrypt.hash(password, 10);

    let agentId = null;
    let purchaseCode = null;

    // 🔎 Agent unlock code
    const agentResult = await db.query(
      `SELECT id, active FROM agents WHERE unlock_code = $1 LIMIT 1`,
      [promoCode]
    );

    if (agentResult.rows.length) {
      const agent = agentResult.rows[0];
      if (!agent.active) {
        const failure = await recordAccessCodeFailure(codeScope, promoCode);
        return reply(false, {
          error: failure.locked
            ? "Too many incorrect codes. Try again in 15 minutes."
            : "That access code is not valid",
        }, failure.locked ? 429 : 200);
      }
      agentId = agent.id;
    } else {
      // Personal access code issued by the VitaLink website.
      const purchaseResult = await db.query(
        `SELECT code, redeemed FROM activation_codes WHERE code = $1 LIMIT 1`,
        [promoCode]
      );

      if (purchaseResult.rows.length) {
        const pc = purchaseResult.rows[0];
        if (pc.redeemed) {
          const failure = await recordAccessCodeFailure(codeScope, promoCode);
          return reply(false, {
            error: failure.locked
              ? "Too many incorrect codes. Try again in 15 minutes."
              : "That access code has already been used",
          }, failure.locked ? 429 : 200);
        }

        purchaseCode = pc.code;

      } else {
        const failure = await recordAccessCodeFailure(codeScope, promoCode);
        return reply(false, {
          error: failure.locked
            ? "Too many incorrect codes. Try again in 15 minutes."
            : "That access code is not valid",
        }, failure.locked ? 429 : 200);
      }
    }

    await clearAccessCodeFailures(codeScope);

    // ✅ Insert user
    const result = await db.query(
      `INSERT INTO users
        (first_name, last_name, email, phone, password_hash, agent_id, purchase_code,
         access_sponsor, relationship_status, messaging_consent_status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING id, email, first_name, last_name, agent_id, purchase_code,
         access_sponsor, relationship_status, messaging_consent_status`,
      [
        firstName,
        lastName,
        email,
        normalizeUsPhone(phone),
        password_hash,
        agentId,
        purchaseCode,
        agentId ? "agent" : "personal",
        agentId ? (relationshipType === "prospect" ? "pending_prospect_confirmation" : "pending_confirmation") : "not_applicable",
        agentId ? "pending" : "not_applicable",
      ]
    );

    const user = result.rows[0];
    if (purchaseCode) {
      await db.query(
        `UPDATE activation_codes
         SET redeemed=true, redeemed_at=NOW(), redeemed_user_id=$1
         WHERE code=$2`,
        [user.id, purchaseCode]
      );
    }
    const sessionToken = await createUserSession(user.id);

    // ✅ Correct device upsert (1 device per user)
    if (deviceId) {
      await db.query(
        `INSERT INTO user_devices
          (user_id, agent_id, device_id, platform, device_status, last_seen_at, created_at, updated_at)
         VALUES ($1,$2,$3,$4,'active',NOW(),NOW(),NOW())
         ON CONFLICT (user_id, device_id) WHERE user_id IS NOT NULL AND device_id IS NOT NULL
         DO UPDATE SET platform=EXCLUDED.platform, device_status='active', last_seen_at=NOW(), updated_at=NOW()`,
        [user.id, agentId, deviceId, platform || "unknown"]
      );
      await recordDeviceEvent(user.id, deviceId, "registration", null, platform);
    }

    return reply(true, {
      message: "User registered successfully ✅",
      user: {
        ...user,
        session_token: sessionToken,
      },
    });
  } catch (err) {
    console.error("❌ register_user error:", err);
    return reply(false, { error: "Server error: " + err.message });
  }
};
