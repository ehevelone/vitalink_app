const db = require("./services/db");
const crypto = require("crypto");
const { decrypt } = require("./encrypt.js"); // ✅ FIXED

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

    // 🔥 SAFE TOKEN EXTRACTION (FIXED)
    let token = event.queryStringParameters?.token;

    if (!token && event.rawQuery) {
      const params = new URLSearchParams(event.rawQuery);
      token = params.get("token");
    }

    console.log("TOKEN RECEIVED:", token);

    if (!token) {
      return reply(400, {
        success: false,
        error: "Missing token",
      });
    }

    const token_hash = crypto
      .createHash("sha256")
      .update(token)
      .digest("hex");

    console.log("TOKEN HASH:", token_hash);

    const tokenRes = await db.query(
      `
      SELECT id, encrypted_data, raw_data
      FROM public.profiles
      WHERE token_hash = $1
        AND (qr_revoked IS NULL OR qr_revoked = false)
      LIMIT 1
      `,
      [token_hash]
    );

    console.log("DB RESULT COUNT:", tokenRes.rows.length);

    if (!tokenRes.rows.length) {
      return reply(404, {
        success: false,
        error: "Invalid or expired QR",
      });
    }

    const profileId = tokenRes.rows[0].id;
    const row = tokenRes.rows[0];

    const encrypted = row.encrypted_data;
    const raw = row.raw_data;

    let data = {};

    if (encrypted) {
      try {
        data = JSON.parse(decrypt(encrypted));
      } catch (e) {
        console.error("DECRYPT ERROR:", e);
        return reply(500, {
          success: false,
          error: "Decrypt failed",
        });
      }
    } else if (raw) {
      try {
        data = typeof raw === "string" ? JSON.parse(raw) : raw;
      } catch (e) {
        console.error("RAW PARSE ERROR:", e);
        return reply(500, {
          success: false,
          error: "Raw data parse failed",
        });
      }
    } else {
      return reply(404, {
        success: false,
        error: "No emergency data found",
      });
    }

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

    if (!meds.length && Array.isArray(data.medications)) {
      meds = data.medications;
    }

    const emergency = data.emergency || {};

    const contactName =
      emergency.contact ||
      data.emergencyContactName ||
      data.contact ||
      "";

    const contactPhone =
      emergency.phone ||
      data.emergencyContactPhone ||
      data.phone ||
      "";

    return reply(200, {
      success: true,
      emergency: {
        name: data.fullName || data.name || "",
        dob: data.dob || "",
        bloodType: emergency.bloodType || data.bloodType || "",
        organDonor: emergency.organDonor || data.organDonor || false,

        emergencyContactName: contactName,
        emergencyContactPhone: contactPhone,

        allergies: emergency.allergies || data.allergies || "",
        conditions: emergency.conditions || data.conditions || "",
        implants: emergency.implants || data.implants || "",
        procedures: emergency.procedures || data.procedures || "",

        meds,
        providers: data.providers || data.doctors || [],
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