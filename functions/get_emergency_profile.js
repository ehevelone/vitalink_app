const db = require("./services/db");
const crypto = require("crypto");

// 🔐 ENV KEY (same as save)
const key = Buffer.from(process.env.ENCRYPTION_KEY, "hex");

// 🔐 DECRYPT
function decrypt(encryptedText){
  const parts = encryptedText.split(":");
  const iv = Buffer.from(parts[0], "hex");
  const encrypted = parts[1];

  const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);

  let decrypted = decipher.update(encrypted, "hex", "utf8");
  decrypted += decipher.final("utf8");

  return decrypted;
}

exports.handler = async (event) => {

  const headers = {
    "Access-Control-Allow-Origin": "*", // 🔥 must allow scan access
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "GET, OPTIONS"
  };

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers,
      body: ""
    };
  }

  try {

    const id = event.queryStringParameters?.id;

    if (!id) {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ success:false, error:"Missing id" })
      };
    }

    const result = await db.query(
      `
      SELECT encrypted_data
      FROM emergency_profiles
      WHERE id = $1
      LIMIT 1
      `,
      [id]
    );

    if (!result.rows || result.rows.length === 0) {
      return {
        statusCode: 404,
        headers,
        body: JSON.stringify({ success:false, error:"Not found" })
      };
    }

    const encrypted = result.rows[0].encrypted_data;

    // 🔐 DECRYPT
    let data;

    try {
      const decrypted = decrypt(encrypted);
      data = JSON.parse(decrypted);
    } catch (e) {
      console.error("decrypt fail:", e);

      return {
        statusCode: 500,
        headers,
        body: JSON.stringify({ success:false, error:"Decrypt failed" })
      };
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        data: data
      })
    };

  } catch (err) {
    console.error("get_emergency_profile error:", err);

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