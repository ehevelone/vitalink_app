const crypto = require("crypto");
const db = require("./services/db");
const { verifyUserSession } = require("./services/user-auth");

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

function clean(value) {
  const text = (value ?? "").toString().trim();
  return text || null;
}

function hashCode(code) {
  return crypto
    .createHash("sha256")
    .update(String(code || "").trim().toUpperCase())
    .digest("hex");
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method not allowed" });
  }

  try {
    const body = JSON.parse(event.body || "{}");
    const code = clean(body.code || body.onboardingCode)?.toUpperCase();
    const userId = clean(body.userId || body.user_id);
    const sessionToken = clean(body.sessionToken);

    if (!code || !userId || !sessionToken) {
      return reply(400, {
        success: false,
        error: "Missing onboarding code or user session",
      });
    }

    if (!(await verifyUserSession(userId, sessionToken))) {
      return reply(403, { success: false, error: "Unauthorized" });
    }

    await db.query(`
      DELETE FROM assisted_client_onboarding
      WHERE expires_at <= NOW()
        AND claimed_at IS NULL
    `);

    const result = await db.query(
      `
      DELETE FROM assisted_client_onboarding
      WHERE invite_code_hash = $1
        AND claimed_at IS NULL
        AND expires_at > NOW()
      RETURNING id
      `,
      [hashCode(code)]
    );

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "This onboarding session has expired and cannot be reopened.",
      });
    }

    return reply(200, {
      success: true,
      claimed: true,
    });
  } catch (err) {
    console.error("claim_assisted_onboarding error:", err);
    return reply(500, { success: false, error: err.message });
  }
};
