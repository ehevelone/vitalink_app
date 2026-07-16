const { Pool } = require("pg");
const bcrypt = require("bcryptjs");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
}

function clean(value) {
  return String(value || "").trim();
}

function normalizeCode(value) {
  return clean(value).toUpperCase().replace(/\s+/g, "");
}

function generateRsmEnrollCode(prefix = "RSM", length = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `${prefix}-${code}`;
}

async function createInviteCode(client) {
  for (let i = 0; i < 8; i++) {
    const code = generateRsmEnrollCode();
    const existing = await client.query(
      "SELECT id FROM rsms WHERE invite_code = $1 LIMIT 1",
      [code]
    );
    if (existing.rows.length === 0) return code;
  }
  throw new Error("Unable to generate unique invite code");
}

exports.handler = async function (event) {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  const configuredCode = normalizeCode(process.env.RSM_CREATION_CODE);
  if (!configuredCode) {
    return reply(500, {
      success: false,
      error: "RSM creation is not configured"
    });
  }

  let body = {};
  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const name = clean(body.name);
  const email = clean(body.email).toLowerCase();
  const phone = clean(body.phone);
  const region = clean(body.region);
  const password = String(body.password || "");
  const creationCode = normalizeCode(body.creationCode);

  if (!name || !email || !phone || !region || !password || !creationCode) {
    return reply(400, { success: false, error: "All fields are required" });
  }

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return reply(400, { success: false, error: "Enter a valid email address" });
  }

  if (password.length < 8) {
    return reply(400, {
      success: false,
      error: "Password must be at least 8 characters"
    });
  }

  if (creationCode !== configuredCode) {
    return reply(403, { success: false, error: "Invalid RSM creation code" });
  }

  const client = await pool.connect();

  try {
    const hashedPassword = await bcrypt.hash(password, 12);

    const existing = await client.query(
      `SELECT id, active, password_hash, invite_code
       FROM rsms
       WHERE LOWER(TRIM(email)) = $1
       LIMIT 1`,
      [email]
    );

    if (existing.rows.length > 0) {
      const rsm = existing.rows[0];

      if (rsm.active === true && rsm.password_hash !== "PENDING_SETUP") {
        return reply(409, {
          success: false,
          error: "RSM account already exists. Use RSM login or forgot password."
        });
      }

      const inviteCode = rsm.invite_code || await createInviteCode(client);

      await client.query(
        `UPDATE rsms
         SET name = $2,
             email = $3,
             phone = $4,
             region = $5,
             password_hash = $6,
             active = true,
             role = 'rsm',
             invite_code = $7,
             onboard_token = NULL,
             onboard_token_expires = NULL
         WHERE id = $1`,
        [rsm.id, name, email, phone, region, hashedPassword, inviteCode]
      );

      return reply(200, {
        success: true,
        recovered: true,
        invite_code: inviteCode
      });
    }

    const inviteCode = await createInviteCode(client);

    await client.query(
      `INSERT INTO rsms
        (role, email, password_hash, name, region, phone, active, created_at, invite_code)
       VALUES
        ('rsm', $1, $2, $3, $4, $5, true, NOW(), $6)`,
      [email, hashedPassword, name, region, phone, inviteCode]
    );

    return reply(200, {
      success: true,
      invite_code: inviteCode
    });
  } catch (err) {
    console.error("rsm-register error:", err);
    return reply(500, { success: false, error: "Server error" });
  } finally {
    client.release();
  }
};
