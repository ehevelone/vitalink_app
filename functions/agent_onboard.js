// functions/agent_onboard.js

const db = require("./services/db");
const crypto = require("crypto");

// 🔹 Generate AG-XXXXXXXXXX unlock code
function generateUnlockCode(prefix = "AG", length = 10) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `${prefix}-${code}`;
}

// 🔹 Generate secure onboarding token
function generateToken() {
  return crypto.randomBytes(16).toString("hex");
}

exports.handler = async (event) => {
  try {
    // ✅ Allow CORS preflight
    if (event.httpMethod === "OPTIONS") {
      return {
        statusCode: 200,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers": "Content-Type",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
        },
        body: "",
      };
    }

    // ✅ QR scans hit via GET
    if (event.httpMethod !== "GET") {
      return {
        statusCode: 405,
        body: "Method Not Allowed",
      };
    }

    // 1️⃣ Generate unlock + token
    const unlockCode = generateUnlockCode();
    const onboardToken = generateToken();

    // 2️⃣ Insert NEW agent row
    const result = await db.query(
      `
      INSERT INTO agents (
        role,
        active,
        unlock_code,
        onboard_token,
        created_at
      )
      VALUES (
        'agent',
        FALSE,
        $1,
        $2,
        NOW()
      )
      RETURNING id;
      `,
      [unlockCode, onboardToken]
    );

    const agentId = result.rows[0].id;

    // 3️⃣ Redirect to WEBSITE onboarding page
    const redirectUrl =
      `https://myvitalink.app/agent-onboard.html?token=${encodeURIComponent(onboardToken)}`;

    console.log("=================================");
    console.log(`✅ Agent Created: ${agentId}`);
    console.log(`🔐 Unlock Code: ${unlockCode}`);
    console.log(`🔑 Token: ${onboardToken}`);
    console.log(`🔗 Redirecting to: ${redirectUrl}`);
    console.log("=================================");

    return {
      statusCode: 302,
      headers: {
        Location: redirectUrl,
      },
    };

  } catch (err) {
    console.error("❌ agent_onboard error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: err.message,
      }),
    };
  }
};
