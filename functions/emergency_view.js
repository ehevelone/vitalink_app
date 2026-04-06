const db = require("./services/db");
const crypto = require("crypto");
const { v4: uuidv4, v5: uuidv5 } = require("uuid");

// 🔐 ENV KEY
const key = Buffer.from(process.env.ENCRYPTION_KEY, "hex");

// UUID FIX
function ensureUuid(id) {
  if (!id) return uuidv4();
  const uuidRegex = /^[0-9a-fA-F-]{36}$/;
  if (uuidRegex.test(id)) return id;
  return uuidv5(id.toString(), uuidv5.URL);
}

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

    let data;

    try {
      const decrypted = decrypt(result.rows[0].encrypted_data);
      data = JSON.parse(decrypted);
      console.log("DECRYPTED DATA:", JSON.stringify(data, null, 2));
    } catch (e) {
      return reply(500, {
        success: false,
        error: "Decrypt failed",
      });
    }

    const profileRes = await db.query(
      `
      SELECT id
      FROM profiles
      WHERE id::text = $1 OR id::text = $2
      LIMIT 1
      `,
      [rawId, normalizedId]
    );

    let meds = [];

    if (profileRes.rows.length) {
      const profileId = profileRes.rows[0].id;

      const medsRes = await db.query(
        `
        SELECT name, dose, frequency
        FROM meds
        WHERE profile_id = $1
        ORDER BY name
        `,
        [profileId]
      );

      meds = medsRes.rows.map(m => ({
        name: m.name || "",
        dose: m.dose || "",
        frequency: m.frequency || ""
      }));
    }

    if (!meds.length && Array.isArray(data.meds)) {
      meds = data.meds;
    }

    // 🔥 FIX: SUPPORT BOTH FIELD TYPES
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