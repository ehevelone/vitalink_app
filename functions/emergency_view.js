const db = require("./services/db");
const crypto = require("crypto");

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

    // 🔥 LOOKUP PROFILE DIRECTLY
    const result = await db.query(
      `
      SELECT *
      FROM public.profiles
      WHERE token_hash = $1
        AND (qr_revoked IS NULL OR qr_revoked = false)
      LIMIT 1
      `,
      [token_hash]
    );

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "Invalid or expired QR",
      });
    }

    const profile = result.rows[0];

    // 🔥 PARSE STORED DATA
    let raw = {};

    try {
      raw = profile.raw_data || {};
      if (typeof raw === "string") {
        raw = JSON.parse(raw);
      }
    } catch (e) {
      console.warn("⚠️ Failed to parse raw_data");
    }

    // 🔥 SAFE FIELD MAPPING
    return reply(200, {
      success: true,
      emergency: {
        name: profile.name || raw.name || "",
        dob: profile.dob || raw.dob || "",
        bloodType: raw.bloodType || "",
        organDonor: raw.organDonor || false,

        emergencyContactName:
          raw.emergencyContactName || raw.contact || "",

        emergencyContactPhone:
          raw.emergencyContactPhone || raw.phone || "",

        allergies:
          profile.allergies
            ? JSON.parse(profile.allergies)
            : raw.allergies || [],

        conditions:
          profile.conditions
            ? JSON.parse(profile.conditions)
            : raw.conditions || [],

        meds:
          profile.medications
            ? JSON.parse(profile.medications)
            : raw.medications || [],

        providers: raw.providers || [],
        notes: profile.notes || raw.notes || "",
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