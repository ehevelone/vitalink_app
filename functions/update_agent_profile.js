// functions/update_agent_profile.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    // ✅ CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    // ✅ Safe body parsing
    let body = {};
    try {
      if (event.isBase64Encoded) {
        body = JSON.parse(
          Buffer.from(event.body, "base64").toString("utf8")
        );
      } else {
        body = JSON.parse(event.body || "{}");
      }
    } catch (e) {
      return reply(400, {
        success: false,
        error: "Invalid request body",
      });
    }

    const {
      email,
      name,
      phone,
      npn,
      agencyName,
      agencyAddress,
      agencyPhone, // 🔥 ADDED
      password,
    } = body;

    if (!email) {
      return reply(400, {
        success: false,
        error: "Email is required",
      });
    }

    // ✅ Build dynamic update
    const updates = [];
    const values = [];
    let idx = 1;

    if (name) {
      updates.push(`name = $${idx++}`);
      values.push(name);
    }
    if (phone) {
      updates.push(`phone = $${idx++}`);
      values.push(phone);
    }
    if (npn) {
      updates.push(`npn = $${idx++}`);
      values.push(npn);
    }
    if (agencyName) {
      updates.push(`agency_name = $${idx++}`);
      values.push(agencyName);
    }
    if (agencyAddress) {
      updates.push(`agency_address = $${idx++}`);
      values.push(agencyAddress);
    }

    // 🔥 NEW FIELD SAVE
    if (agencyPhone) {
      updates.push(`agency_phone = $${idx++}`);
      values.push(agencyPhone);
    }

    if (password) {
      const hashed = await bcrypt.hash(password, 10);
      updates.push(`password_hash = $${idx++}`);
      values.push(hashed);
    }

    if (!updates.length) {
      return reply(400, {
        success: false,
        error: "No fields provided to update",
      });
    }

    values.push(email.trim());

    const query = `
      UPDATE agents
      SET ${updates.join(", ")}
      WHERE LOWER(email) = LOWER($${idx})
      RETURNING
        id,
        email,
        name,
        phone,
        npn,
        agency_name,
        agency_address,
        agency_phone, -- 🔥 ADDED
        active,
        role;
    `;

    const result = await db.query(query, values);

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "Agent not found",
      });
    }

    return reply(200, {
      success: true,
      message: "Agent profile updated ✅",
      agent: result.rows[0],
    });

  } catch (err) {
    console.error("❌ update_agent_profile error:", err);
    return reply(500, {
      success: false,
      error: "Server error while updating agent ❌",
    });
  }
};