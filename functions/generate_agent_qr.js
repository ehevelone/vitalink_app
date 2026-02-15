// functions/generateAgentQR.js

const db = require("./services/db");
const QRCode = require("qrcode");

function generateCode(prefix = "AGENT", length = 6) {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < length; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return `${prefix}-${code}`;
}

async function generateUniqueCode(agentId) {
  let attempts = 0;

  while (attempts < 5) {
    const code = generateCode("AGENT", 6);

    const existing = await db.query(
      "SELECT id FROM promo_codes WHERE code = $1 LIMIT 1",
      [code]
    );

    if (existing.rowCount === 0) {
      return code;
    }

    attempts++;
  }

  throw new Error("Failed to generate unique code");
}

exports.handler = async (event) => {
  try {
    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        body: JSON.stringify({ error: "Method not allowed" }),
      };
    }

    const { agentId } = JSON.parse(event.body || "{}");

    if (!agentId) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "agentId required" }),
      };
    }

    // 🔐 Generate unique promo code
    const code = await generateUniqueCode(agentId);

    await db.query(
      `
      INSERT INTO promo_codes 
      (code, max_uses, used_count, created_at, agent_id)
      VALUES ($1, $2, 0, NOW(), $3)
      `,
      [code, null, agentId] // null max_uses = unlimited
    );

    // 🔗 Build deep link (must match Android manifest)
    const deepLink = `vitalink://register?agent=${encodeURIComponent(agentId)}&promo=${encodeURIComponent(code)}`;

    // 🔲 Generate QR
    const qrDataUrl = await QRCode.toDataURL(deepLink);

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        success: true,
        code,
        deepLink,
        qr: qrDataUrl,
      }),
    };
  } catch (err) {
    console.error("❌ generateAgentQR error:", err);

    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        success: false,
        error: "Server error",
      }),
    };
  }
};
