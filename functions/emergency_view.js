const db = require("./services/db");
const crypto = require("crypto");

// 🔐 ENV KEY
const key = Buffer.from(process.env.ENCRYPTION_KEY, "hex");

// DECRYPT
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
    if (event.httpMethod !== "GET") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    const token = event.queryStringParameters?.token;

    if (!token) {
      return reply(400, {
        success: false,
        error: "Missing token",
      });
    }

    // 🔐 HASH TOKEN
    const token_hash = crypto
      .createHash("sha256")
      .update(token)
      .digest("hex");

    // 🔍 LOOKUP TOKEN
    const tokenRes = await db.query(
      `
      SELECT profile_id
      FROM public.qr_tokens
      WHERE token_hash = $1
        AND (revoked IS NULL OR revoked = false)
      LIMIT 1
      `,
      [token_hash]
    );

    if (!tokenRes.rows.length) {
      return reply(404, {
        success: false,
        error: "Invalid or expired QR",
      });
    }

    const profileId = tokenRes.rows[0].profile_id;

    if (!profileId) {
      return reply(404, {
        success: false,
        error: "Profile not found",
      });
    }

    // 🔥 LOAD ENCRYPTED PROFILE
    const result = await db.query(
      `
      SELECT encrypted_data
      FROM emergency_profiles
      WHERE id = $1
      LIMIT 1
      `,
      [profileId]
    );

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "Emergency profile not found",
      });
    }

    let data;

    try {
      const decrypted = decrypt(result.rows[0].encrypted_data);
      data = JSON.parse(decrypted);
    } catch (e) {
      return reply(500, {
        success: false,
        error: "Decrypt failed",
      });
    }

    // 🔥 GET MEDS
    const medsRes = await db.query(
      `
      SELECT name, dose, frequency
      FROM meds
      WHERE profile_id = $1
      ORDER BY name
      `,
      [profileId]
    );

    let meds = medsRes.rows.map(m => ({
      name: m.name || "",
      dose: m.dose || "",
      frequency: m.frequency || ""
    }));

    if (!meds.length && Array.isArray(data.meds)) {
      meds = data.meds;
    }

    // 🔥 CONTACT SAFE MAPPING
    const contactName =
      data.emergencyContactName ||
      data.contact ||
      "";

    const contactPhone =
      data.emergencyContactPhone ||
      data.phone ||
      "";

    return reply(200, {
      success: true,
      emergency: {
        name: data.name || "",
        dob: data.dob || "",
        bloodType: data.bloodType || "",
        organDonor: data.organDonor || false,

        emergencyContactName: contactName,
        emergencyContactPhone: contactPhone,

        allergies: data.allergies || "",
        conditions: data.conditions || "",
        implants: data.implants || "",
        procedures: data.procedures || "",

        meds,
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