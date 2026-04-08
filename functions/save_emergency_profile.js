const db = require("./services/db");
const crypto = require("crypto");

// 🔐 SAFE KEY (NO INIT CRASH)
function getKey() {
  const raw = process.env.ENCRYPTION_KEY;

  if (!raw) {
    console.warn("⚠️ ENCRYPTION_KEY missing");
    return null;
  }

  try {
    const k = Buffer.from(raw, "hex");

    if (k.length !== 32) {
      console.warn("⚠️ ENCRYPTION_KEY wrong length");
      return null;
    }

    return k;

  } catch (e) {
    console.warn("⚠️ ENCRYPTION_KEY invalid format");
    return null;
  }
}

// 🔐 ENCRYPT
function encrypt(text) {
  const key = getKey();

  if (!key) {
    return text;
  }

  const iv = crypto.randomBytes(16);
  const cipher = crypto.createCipheriv("aes-256-cbc", key, iv);

  let encrypted = cipher.update(text, "utf8", "hex");
  encrypted += cipher.final("hex");

  return iv.toString("hex") + ":" + encrypted;
}

exports.handler = async (event) => {

  const headers = {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  try {

    let body = {};

    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success: false, error: "Invalid JSON" })
      };
    }

    const { profile_id, data } = body;

    if (!profile_id || !data) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success: false, error: "Missing profile_id or data" })
      };
    }

    const encrypted = encrypt(JSON.stringify(data));

    // 🔥 SAVE EMERGENCY PAYLOAD TO emergency_profiles
    await db.query(
      `
      INSERT INTO emergency_profiles (id, encrypted_data, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (id)
      DO UPDATE SET
        encrypted_data = EXCLUDED.encrypted_data,
        updated_at = NOW()
      `,
      [profile_id, encrypted]
    );

    // 🔥 GET EXISTING TOKEN + HASH FROM profiles
    const tokenRes = await db.query(
      `
      SELECT qr_token, token_hash
      FROM profiles
      WHERE id = $1
      LIMIT 1
      `,
      [profile_id]
    );

    let qr_token = tokenRes.rows[0]?.qr_token || null;
    let token_hash = tokenRes.rows[0]?.token_hash || null;

    // ✅ CREATE TOKEN IF MISSING
    if (!qr_token) {
      qr_token = crypto.randomBytes(16).toString("hex");
    }

    // ✅ ALWAYS KEEP HASH IN SYNC WITH TOKEN
    token_hash = crypto
      .createHash("sha256")
      .update(qr_token)
      .digest("hex");

    // 🔥 SAVE BOTH TO profiles
    await db.query(
      `
      UPDATE profiles
      SET qr_token = $1,
          token_hash = $2,
          qr_revoked = false
      WHERE id = $3
      `,
      [qr_token, token_hash, profile_id]
    );

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        qr_token
      })
    };

  } catch (err) {
    console.error("save_emergency_profile error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success: false,
        error: "Server error",
        details: err.message
      })
    };
  }
};