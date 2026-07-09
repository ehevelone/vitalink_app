// functions/register_user.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");
const crypto = require("crypto");

function reply(success, obj = {}) {
  return {
    statusCode: 200,
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
    const { firstName, lastName, phone, password, platform } = body;
    const email = normalizeEmail(body.email);
    const promoCode = normalizeCode(body.promoCode);

    await ensureUserSessionColumns();

    if (!firstName || !lastName || !email || !password || !promoCode) {
      return reply(false, { error: "Missing required fields" });
    }

    const emailError = getEmailValidationError(email);
    if (emailError) {
      return reply(false, { error: emailError });
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
        return reply(false, { error: "Agent subscription inactive ❌" });
      }
      agentId = agent.id;
    } else {
      // 🔎 Purchase Code
      const purchaseResult = await db.query(
        `SELECT code, redeemed FROM purchase_codes WHERE code = $1 LIMIT 1`,
        [promoCode]
      );

      if (purchaseResult.rows.length) {
        const pc = purchaseResult.rows[0];
        if (pc.redeemed) {
          return reply(false, { error: "Purchase code already used ❌" });
        }

        purchaseCode = pc.code;

        await db.query(
          `UPDATE purchase_codes SET redeemed = true, redeemed_at = now() WHERE code = $1`,
          [promoCode]
        );
      } else {
        return reply(false, { error: "Invalid agent or purchase promo code ❌" });
      }
    }

    // ✅ Insert user
    const result = await db.query(
      `INSERT INTO users (first_name, last_name, email, phone, password_hash, agent_id, purchase_code)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, email, first_name, last_name, agent_id, purchase_code`,
      [
        firstName,
        lastName,
        email,
        normalizeUsPhone(phone),
        password_hash,
        agentId,
        purchaseCode,
      ]
    );

    const user = result.rows[0];
    const sessionToken = await createUserSession(user.id);

    // ✅ Correct device upsert (1 device per user)
    await db.query(
      `INSERT INTO user_devices (user_id, platform, created_at, updated_at)
       VALUES ($1, $2, NOW(), NOW())
       ON CONFLICT ON CONSTRAINT user_devices_user_id_unique
       DO UPDATE SET platform = EXCLUDED.platform, updated_at = NOW()`,
      [user.id, platform || "unknown"]
    );

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
