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

    // 🔥 UUID VALIDATION
    const uuidRegex =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    if (typeof profile_id !== "string" || !uuidRegex.test(profile_id)) {
      console.error("❌ INVALID PROFILE ID:", profile_id);

      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({
          success: false,
          error: "Invalid profile_id format"
        })
      };
    }

    // 🔐 ENCRYPT DATA
    const encrypted = encrypt(JSON.stringify(data));

    // 🔥 SAVE EMERGENCY DATA
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

    // 🔥 CHECK PROFILE / TOKEN
    let tokenRes = await db.query(
      `
      SELECT qr_token
      FROM profiles
      WHERE id = $1
      LIMIT 1
      `,
      [profile_id]
    );

    let qr_token = tokenRes.rows[0]?.qr_token;

    // 🔥 AUTO-CREATE PROFILE IF MISSING (FIX)
    if (!qr_token) {
      console.warn("⚠️ PROFILE NOT FOUND — CREATING:", profile_id);

      const newToken = crypto.randomBytes(16).toString("hex");

      await db.query(
        `
        INSERT INTO profiles (id, qr_token, created_at)
        VALUES ($1, $2, NOW())
        ON CONFLICT (id) DO NOTHING
        `,
        [profile_id, newToken]
      );

      qr_token = newToken;

      console.log("✅ NEW TOKEN CREATED:", qr_token);
    }

    console.log("✅ USING TOKEN:", qr_token);

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        qr_token
      })
    };

  } catch (err) {
    console.error("❌ save_emergency_profile error:", err);

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