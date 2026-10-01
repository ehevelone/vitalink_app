const db = require("./services/db");
const {
  checkAccessCodeLimit,
  clearAccessCodeFailures,
  rateLimitScope,
  recordAccessCodeFailure,
  requestIp,
} = require("./services/access-code-rate-limit");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (statusCode, body) => ({ statusCode, headers, body: JSON.stringify(body) });
const normalize = (value) => String(value || "").replace(/[\u2010-\u2015\u2212]/g, "-").replace(/[^A-Za-z0-9-]/g, "").trim().toUpperCase();

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") return reply(200, {});
    if (event.httpMethod !== "POST") return reply(405, { success: false, error: "Method Not Allowed" });
    const scope = rateLimitScope("access-code", requestIp(event));
    const limit = await checkAccessCodeLimit(scope);
    if (!limit.allowed) {
      return reply(429, {
        success: false,
        error: "Too many incorrect codes. Try again in 15 minutes.",
        retryAfterSeconds: limit.retryAfterSeconds,
      });
    }
    const code = normalize(JSON.parse(event.body || "{}").code);
    if (!code) return reply(400, { success: false, error: "Enter an access code" });

    const agent = await db.query(
      `SELECT id, name, agency_name FROM agents WHERE unlock_code=$1 AND active=true LIMIT 1`,
      [code]
    );
    if (agent.rows.length) {
      await clearAccessCodeFailures(scope);
      return reply(200, { success: true, type: "agent", agent: agent.rows[0] });
    }

    await db.query(`ALTER TABLE activation_codes ADD COLUMN IF NOT EXISTS redeemed BOOLEAN NOT NULL DEFAULT FALSE`);
    const personal = await db.query(
      `SELECT code, redeemed FROM activation_codes WHERE code=$1 LIMIT 1`,
      [code]
    );
    if (personal.rows.length && personal.rows[0].redeemed !== true) {
      await clearAccessCodeFailures(scope);
      return reply(200, { success: true, type: "personal" });
    }
    const failure = await recordAccessCodeFailure(scope, code);
    if (failure.locked) {
      return reply(429, {
        success: false,
        error: "Too many incorrect codes. Try again in 15 minutes.",
        retryAfterSeconds: 15 * 60,
      });
    }
    return reply(404, { success: false, error: "That access code is not valid" });
  } catch (err) {
    console.error("validate_access_code error:", err);
    return reply(500, { success: false, error: "Server error" });
  }
};
