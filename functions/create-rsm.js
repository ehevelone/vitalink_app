// functions/create-rsm.js
const crypto = require("crypto");
const { requireAdmin } = require("./_adminAuth");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = (process.env.PUBLIC_SITE_URL || "https://myvitalink.app").replace(/\/$/, "");

// Generate permanent RSM agent enrollment code
function generateRsmEnrollCode(prefix = "RSM", length = 8) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `${prefix}-${code}`;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type, x-admin-token, x-admin-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  const auth = await requireAdmin(event);
  if (auth.error) {
    return { statusCode: 401, headers: corsHeaders, body: auth.error };
  }

  try {
    const { email, phone } = JSON.parse(event.body || "{}");

    if (!email || !phone) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Missing email or phone"
      };
    }

    const client = await pool.connect();

    const existing = await client.query(
      "SELECT id, active, password_hash FROM rsms WHERE email=$1 LIMIT 1",
      [email]
    );

    if (existing.rows.length > 0) {
      const rsm = existing.rows[0];

      if (rsm.active === true && rsm.password_hash !== "PENDING_SETUP") {
        client.release();
        return {
          statusCode: 400,
          headers: corsHeaders,
          body: "RSM already exists"
        };
      }

      const token = crypto.randomBytes(24).toString("hex");
      const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

      await client.query(
        `UPDATE rsms
         SET phone = $2,
             onboard_token = $3,
             onboard_token_expires = $4,
             password_hash = CASE
               WHEN password_hash IS NULL OR password_hash = '' THEN 'PENDING_SETUP'
               ELSE password_hash
             END
         WHERE id = $1`,
        [rsm.id, phone, token, expires]
      );

      client.release();

      const onboardingUrl = `${SITE}/rsm-onboard?token=${encodeURIComponent(token)}`;

      return {
        statusCode: 200,
        headers: corsHeaders,
        body: JSON.stringify({
          success: true,
          recovered: true,
          onboard_url: onboardingUrl,
          onboard_token: token
        })
      };
    }

    const token = crypto.randomBytes(24).toString("hex");
    const expires = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    // Required because password_hash is NOT NULL
    const tempPasswordHash = "PENDING_SETUP";

    // Generate permanent agent enrollment code
    const inviteCode = generateRsmEnrollCode();

    await client.query(
      `INSERT INTO rsms 
        (role, email, password_hash, name, region, phone, active, created_at, onboard_token, onboard_token_expires, invite_code) 
       VALUES ('rsm', $1, $2, $3, $4, $5, false, NOW(), $6, $7, $8)`,
      [
        email,
        tempPasswordHash,
        "",        // name placeholder
        "",        // region placeholder
        phone,
        token,
        expires,
        inviteCode
      ]
    );

    client.release();

    const onboardingUrl = `${SITE}/rsm-onboard?token=${encodeURIComponent(token)}`;

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        onboard_url: onboardingUrl,
        onboard_token: token,
        invite_code: inviteCode
      })
    };

  } catch (err) {
    console.error("create-rsm error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }
};
