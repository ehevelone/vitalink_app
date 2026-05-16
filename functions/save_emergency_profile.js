const crypto = require("crypto");
const db = require("./services/db");
const { encrypt } = require("./encrypt.js");
const { verifyUserSession } = require("./services/user-auth");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(statusCode, obj) {
  return {
    statusCode,
    headers,
    body: JSON.stringify(obj),
  };
}

function isUuid(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function hashToken(token) {
  return crypto
    .createHash("sha256")
    .update(token)
    .digest("hex");
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, {
      success: false,
      error: "Method Not Allowed",
    });
  }

  try {
    let body = {};

    try {
      body = JSON.parse(event.body || "{}");
    } catch {
      return reply(400, {
        success: false,
        error: "Invalid JSON",
      });
    }

    const profileId = body.profile_id || body.profileId;
    const data = body.data;
    const userId = body.userId || body.user_id;
    const sessionToken = body.sessionToken;

    if (!profileId || !data) {
      return reply(400, {
        success: false,
        error: "Missing profile_id or data",
      });
    }

    if (!isUuid(profileId)) {
      return reply(400, {
        success: false,
        error: "Invalid profile_id format",
      });
    }

    const authorized = await verifyUserSession(userId, sessionToken);

    if (!authorized) {
      return reply(403, {
        success: false,
        error: "Unauthorized",
      });
    }

    const encryptedData = encrypt(JSON.stringify(data));

    const existing = await db.query(
      `
      SELECT id, user_id, qr_token
      FROM profiles
      WHERE id = $1
      LIMIT 1
      `,
      [profileId]
    );

    if (
      existing.rows.length &&
      existing.rows[0].user_id &&
      String(existing.rows[0].user_id) !== String(userId)
    ) {
      return reply(403, {
        success: false,
        error: "Unauthorized profile",
      });
    }

    const token = existing.rows[0]?.qr_token ||
      crypto.randomBytes(16).toString("hex");
    const tokenHash = hashToken(token);
    const name = (data.fullName || data.name || "Emergency Profile")
      .toString()
      .trim();

    await db.query(
      `
      INSERT INTO emergency_profiles (id, encrypted_data, updated_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (id)
      DO UPDATE SET
        encrypted_data = EXCLUDED.encrypted_data,
        updated_at = NOW()
      `,
      [profileId, encryptedData]
    );

    await db.query(
      `
      INSERT INTO profiles (
        id,
        user_id,
        name,
        encrypted_data,
        qr_token,
        token_hash,
        qr_revoked,
        created_at
      )
      VALUES ($1,$2,$3,$4,$5,$6,false,NOW())
      ON CONFLICT (id)
      DO UPDATE SET
        user_id = COALESCE(profiles.user_id, EXCLUDED.user_id),
        name = EXCLUDED.name,
        encrypted_data = EXCLUDED.encrypted_data,
        token_hash = EXCLUDED.token_hash
      `,
      [
        profileId,
        userId,
        name || "Emergency Profile",
        encryptedData,
        token,
        tokenHash,
      ]
    );

    return reply(200, {
      success: true,
      qr_token: token,
    });
  } catch (err) {
    console.error("save_emergency_profile error:", err);

    return reply(500, {
      success: false,
      error: "Server error",
      details: err.message,
    });
  }
};
