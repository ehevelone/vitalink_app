// functions/resolve_token.js
const db = require("./services/db");

/**
 * Resolve an onboarding token to an agent unlock code.
 * Used ONLY for agent claim / onboarding.
 */
exports.handler = async (event) => {
  try {
    const token = event.queryStringParameters?.token;
    if (!token) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Missing token" }),
      };
    }

    // 🔍 Lookup agent by onboarding token
    const result = await db.query(
      `
      SELECT unlock_code, active
      FROM agents
      WHERE onboard_token = $1
      LIMIT 1
      `,
      [token]
    );

    if (!result.rows.length) {
      return {
        statusCode: 404,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ success: false, error: "Invalid token" }),
      };
    }

    const agent = result.rows[0];

    // 🔒 Enforce active agent
    if (!agent.active) {
      return {
        statusCode: 403,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          success: false,
          error: "Agent is inactive",
        }),
      };
    }

    // ✅ Return unlock code
    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        success: true,
        unlock_code: agent.unlock_code,
      }),
    };
  } catch (err) {
    console.error("❌ resolve_token error:", err);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        success: false,
        error: "Server error",
      }),
    };
  }
};
