// functions/emergency_view.js
const db = require("./services/db");

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

    const id =
      event.queryStringParameters?.id ||
      event.queryStringParameters?.profileId;

    if (!id) {
      return reply(400, {
        success: false,
        error: "Missing emergency profile id",
      });
    }

    // 🧍 Load profile + emergency
    const profileRes = await db.query(
      `
      SELECT
        p.id,
        p.full_name,
        p.dob,
        e.contact,
        e.phone,
        e.allergies,
        e.conditions,
        e.blood_type,
        e.organ_donor
      FROM profiles p
      LEFT JOIN emergency e ON e.profile_id = p.id
      WHERE p.id = $1
      LIMIT 1
      `,
      [id]
    );

    if (!profileRes.rows.length) {
      return reply(404, {
        success: false,
        error: "Emergency profile not found",
      });
    }

    const profile = profileRes.rows[0];

    // 💊 Medications
    const medsRes = await db.query(
      `
      SELECT name, dose, frequency
      FROM meds
      WHERE profile_id = $1
      ORDER BY name
      `,
      [id]
    );

    // 🩺 Providers
    const providersRes = await db.query(
      `
      SELECT name, phone
      FROM doctors
      WHERE profile_id = $1
      ORDER BY name
      `,
      [id]
    );

    return reply(200, {
      success: true,
      emergency: {
        name: profile.full_name,
        dob: profile.dob,
        bloodType: profile.blood_type,
        organDonor: profile.organ_donor,
        emergencyContact: profile.contact,
        emergencyPhone: profile.phone,
        allergies: profile.allergies,
        conditions: profile.conditions,
        medications: medsRes.rows,
        providers: providersRes.rows,
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
