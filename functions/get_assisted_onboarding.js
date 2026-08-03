const crypto = require("crypto");
const db = require("./services/db");

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

async function ensureSchema() {
  await db.query(`
    CREATE TABLE IF NOT EXISTS assisted_client_onboarding (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      crm_agent_id TEXT NOT NULL,
      app_agent_id INTEGER,
      crm_client_id UUID,
      invite_code_hash TEXT UNIQUE NOT NULL,
      payload JSONB NOT NULL DEFAULT '{}'::jsonb,
      expires_at TIMESTAMPTZ NOT NULL,
      claimed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);

  await db.query(`
    DELETE FROM assisted_client_onboarding
    WHERE expires_at <= NOW()
      AND claimed_at IS NULL
  `);
}

exports.handler = async (event) => {
  if (event.httpMethod === "OPTIONS") return reply(200, {});

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method not allowed" });
  }

  try {
    await ensureSchema();

    const body = JSON.parse(event.body || "{}");
    const code = clean(body.code || body.onboardingCode)?.toUpperCase();

    if (!code) {
      return reply(400, { success: false, error: "Missing onboarding code" });
    }

    const result = await db.query(
      `
      SELECT id, payload, expires_at
      FROM assisted_client_onboarding
      WHERE invite_code_hash = $1
        AND claimed_at IS NULL
        AND expires_at > NOW()
      LIMIT 1
      `,
      [hashCode(code)]
    );

    if (!result.rows.length) {
      return reply(404, {
        success: false,
        error: "This onboarding session has expired. Please ask your agent to start a new session with you.",
      });
    }

    const row = result.rows[0];

    return reply(200, {
      success: true,
      onboardingId: row.id,
      expiresAt: row.expires_at,
      payload: row.payload || {},
    });
  } catch (err) {
    console.error("get_assisted_onboarding error:", err);
    return reply(500, { success: false, error: err.message });
  }
};
