const db = require("./services/db");
const crypto = require("crypto");

// 🔐 ENV KEY (64 hex chars = 32 bytes)
const key = Buffer.from(process.env.ENCRYPTION_KEY, "hex");

// 🔐 ENCRYPT
function encrypt(text){
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
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    let body = {};

    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error:"Invalid JSON" })
      };
    }

    const { profile_id, data } = body;

    if (!profile_id || !data) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error:"Missing profile_id or data" })
      };
    }

    // 🔐 ENCRYPT DATA
    const encrypted = encrypt(JSON.stringify(data));

    // 💾 UPSERT
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

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true
      })
    };

  } catch (err) {
    console.error("save_emergency_profile error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        success:false,
        error:"Server error"
      })
    };
  }
};