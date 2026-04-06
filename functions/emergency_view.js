// functions/emergency_view.js
const db = require("./services/db");
const crypto = require("crypto");
const { v4: uuidv4, v5: uuidv5 } = require("uuid");

// 🔐 ENV KEY
const key = Buffer.from(process.env.ENCRYPTION_KEY, "hex");

// -------------------------------------------------------------
// 🔥 UUID FIX
// -------------------------------------------------------------
function ensureUuid(id) {
  if (!id) return uuidv4();

  const uuidRegex = /^[0-9a-fA-F-]{36}$/;

  if (uuidRegex.test(id)) return id;

  return uuidv5(id.toString(), uuidv5.URL);
}

// 🔐 DECRYPT
function decrypt(encryptedText) {
  const parts = encryptedText.split(":");
  const iv = Buffer.from(parts[0], "hex");
  const encrypted = parts[1];

  const decipher = crypto.createDecipheriv("aes-256-cbc", key, iv);

  let decrypted = decipher.update(encrypted, "hex", "utf8");
  decrypted += decipher.final("utf8");

  return decrypted;
}

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    // 🔒 GET only
    if (event.httpMethod !== "GET") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    let rawId =
      event.queryStringParameters?.id ||
      event.queryStringParameters?.profileId;

    if (!rawId) {
      return reply(400, {
        success: false,
        error: "Missing emergency profile id",
      });
    }

    rawId = String(rawId).trim();
    const normalizedId = ensureUuid(rawId);

    console.log("🔎 RAW ID:", rawId);
    console.log("🔎 NORMALIZED ID:", normalizedId);

    // 🔐 LOAD ENCRYPTED RECORD
    const result = await db.query(
      `
      SELECT encrypted_data
      FROM emergency_profiles
      WHERE id::text = $1 OR id::text = $2
      LIMIT 1
      `,
      [rawId, normalizedId]
    );

    if (!result.rows || result.rows.length === 0) {
      return reply(404, {
        success: false,
        error: "Emergency profile not found",
      });
    }

    const encrypted = result.rows[0].encrypted_data;

    // 🔐 DECRYPT + PARSE
    let data;

    try {
      const decrypted = decrypt(encrypted);
      data = JSON.parse(decrypted);
    } catch (e) {
      console.error("❌ decrypt fail:", e);
      return reply(500, {
        success: false,
        error: "Decrypt failed",
      });
    }

    // 🎯 RETURN DATA (same structure your frontend expects)
    return reply(200, {
      success: true,
      emergency: {
        name: data.name || "",
        dob: data.dob || "",
        bloodType: data.bloodType || "",
        organDonor: data.organDonor || false,
        emergencyContact: data.contact || "",
        emergencyPhone: data.phone || "",
        allergies: data.allergies || "",
        conditions: data.conditions || "",
        medications: data.medications || [],
        providers: data.providers || [],
      },
    });

  } catch (err) {
    console.error("❌ emergency_view error:", err);
    return reply(500, {
      success: false,
      error: "Server error loading emergency view",
    });
  }
};