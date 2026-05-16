const db = require("./services/db");

// ✅ CORS HEADERS (PRODUCTION SAFE)
const headers = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

async function verifyUserSession(userId, token) {
  if (!userId || !token) return false;

  await db.query(`
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ
  `);

  const result = await db.query(
    `
    SELECT id
    FROM users
    WHERE id = $1
      AND session_token = $2
      AND session_expires > NOW()
    LIMIT 1
    `,
    [userId, token]
  );

  return result.rows.length > 0;
}

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers,
      body: JSON.stringify({ error: "Method not allowed" }),
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
        body: JSON.stringify({ error: "Invalid JSON" }),
      };
    }

    let result;

    // 🔥 MULTIPLE UUIDs (CHECKOUT FLOW)
    if (Array.isArray(body.profiles) && body.profiles.length) {

      const ids = body.profiles
        .map(id => String(id))
        .filter(id => id && id.length === 36);

      console.log("PROFILE UUIDS RECEIVED:", ids);

      result = await db.query(
        `
        SELECT id, name, qr_token
        FROM profiles
        WHERE id = ANY($1::uuid[])
        ORDER BY name
        `,
        [ids]
      );

    }

    // 🔥 SINGLE UUID
    else if (body.id) {

      result = await db.query(
        `
        SELECT id, name, qr_token
        FROM profiles
        WHERE id = $1::uuid
        LIMIT 1
        `,
        [body.id]
      );

    }

    // 🔥 USER PROFILE LOAD (ORDER PAGE / APP)
    else if (body.user_id) {
      const authorized =
        await verifyUserSession(body.user_id, body.sessionToken);

      if (!authorized) {
        return {
          statusCode: 403,
          headers,
          body: JSON.stringify({
            success: false,
            error: "Unauthorized",
          }),
        };
      }

      result = await db.query(
        `
        SELECT id, name, qr_token
        FROM profiles
        WHERE user_id = $1
        ORDER BY name ASC
        `,
        [body.user_id]
      );

    }

    // ❌ NOTHING VALID SENT
    else {
      return {
        statusCode: 400,
        headers,
        body: JSON.stringify({ error: "Missing parameters" }),
      };
    }

    return {
      statusCode: 200,
      headers,
      body: JSON.stringify({
        success: true,
        profiles: result.rows || [],
      }),
    };

  } catch (err) {

    console.error("get-profiles error:", err);

    return {
      statusCode: 500,
      headers,
      body: JSON.stringify({
        error: "Server error",
      }),
    };
  }
};
