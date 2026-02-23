// functions/get_agent_promo.js
const db = require("./services/db");

function reply(statusCode, obj) {
  return {
    statusCode,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
    },
    body: JSON.stringify(obj),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return reply(200, {});
    }

    if (event.httpMethod !== "POST") {
      return reply(405, {
        success: false,
        error: "Method Not Allowed",
      });
    }

    let body = {};
    try {
      body = event.isBase64Encoded
        ? JSON.parse(Buffer.from(event.body, "base64").toString("utf8"))
        : JSON.parse(event.body || "{}");
    } catch {
      return reply(400, {
        success: false,
        error: "Invalid request body",
      });
    }

    const { email } = body;

    if (!email) {
      return reply(400, {
        success: false,
        error: "Email required",
      });
    }

    // 1️⃣ Get agent including unlock_code directly from agents table
    const agentResult = await db.query(
      `
      SELECT id, name, email, active, unlock_code
      FROM agents
      WHERE LOWER(email) = LOWER($1)
      LIMIT 1
      `,
      [email.trim()]
    );

    if (!agentResult.rows.length) {
      return reply(404, {
        success: false,
        error: "No agent found",
      });
    }

    const agent = agentResult.rows[0];

    if (!agent.unlock_code) {
      return reply(400, {
        success: false,
        error: "No unlock code found for agent",
      });
    }

    return reply(200, {
      success: true,
      promoCode: agent.unlock_code, // 👈 mapped to existing Flutter field
      active: agent.active ?? false,
      agent: {
        id: agent.id,
        name: agent.name,
        email: agent.email,
      },
    });

  } catch (err) {
    console.error("❌ get_agent_promo error:", err);
    return reply(500, {
      success: false,
      error: "Server error while fetching promo code ❌",
    });
  }
};