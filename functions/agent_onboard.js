// functions/agent_onboard.js

const db = require("./services/db");

// 🔹 Generate AG-XXXXXXXX unlock code
function generateUnlockCode(prefix = "AG", length = 10) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `${prefix}-${code}`;
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

    // ✅ Only allow GET (QR scan)
    if (event.httpMethod !== "GET") {
      return {
        statusCode: 405,
        body: "Method Not Allowed",
      };
    }

    const params = event.queryStringParameters || {};
    const rsmCode = params.rsm;

    if (!rsmCode) {
      return {
        statusCode: 400,
        body: "Missing RSM enrollment code",
      };
    }

    // 🔎 1️⃣ Find RSM by enrollment code
    const rsmResult = await db.query(
      `
      SELECT id, billing_active
      FROM rsms
      WHERE agent_enroll_code = $1
      LIMIT 1
      `,
      [rsmCode]
    );

    if (rsmResult.rows.length === 0) {
      return {
        statusCode: 404,
        body: "Invalid RSM enrollment code",
      };
    }

    const rsm = rsmResult.rows[0];

    // 🚫 BLOCK if office billing inactive
    if (!rsm.billing_active) {
      console.log("Enrollment blocked — billing inactive");

      return {
        statusCode: 403,
        body: "Office billing inactive. Contact your RSM.",
      };
    }

    const rsmId = rsm.id;

    // 🔑 2️⃣ Generate agent unlock code
    const unlockCode = generateUnlockCode();

    // 🧱 3️⃣ Insert agent tied to RSM
    const result = await db.query(
      `
      INSERT INTO agents (
        role,
        active,
        unlock_code,
        rsm_id,
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
      [unlockCode, rsmId]
    );

    const agentId = result.rows[0].id;

    // 🔁 4️⃣ Redirect to claim page
    const redirectUrl =
      `https://myvitalink.app/core-node/agent_claim.html?code=${encodeURIComponent(unlockCode)}`;

    console.log("=================================");
    console.log(`✅ Agent Created: ${agentId}`);
    console.log(`🔐 Unlock Code: ${unlockCode}`);
    console.log(`👤 Bound to RSM ID: ${rsmId}`);
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