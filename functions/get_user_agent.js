// functions/get_user_agent.js
const db = require("./services/db");

function ok(obj) {
  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify({ success: true, ...obj }),
  };
}

function fail(msg, code = 400) {
  return {
    statusCode: code,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify({ success: false, error: msg }),
  };
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod === "OPTIONS") {
      return {
        statusCode: 200,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
        },
        body: "",
      };
    }

    if (event.httpMethod !== "POST") {
      return fail("Method not allowed", 405);
    }

    const { email } = JSON.parse(event.body || "{}");

    if (!email) {
      return fail("Missing user email");
    }

    // 🔎 1️⃣ Find user and their agent_id
    const userResult = await db.query(
      "SELECT agent_id FROM users WHERE email = $1",
      [email.toLowerCase()]
    );

    if (!userResult.rows.length) {
      return fail("User not found", 404);
    }

    const agentId = userResult.rows[0].agent_id;

    if (!agentId) {
      return ok({ agent: null });
    }

    // 🔎 2️⃣ Fetch agent record
    const agentResult = await db.query(
      `SELECT id, name, email, phone, agency_name, agency_address 
       FROM agents 
       WHERE id = $1`,
      [agentId]
    );

    if (!agentResult.rows.length) {
      return fail("Agent not found", 404);
    }

    return ok({ agent: agentResult.rows[0] });

  } catch (e) {
    console.error("❌ get_user_agent error:", e);
    return fail("Server error: " + e.message, 500);
  }
};
