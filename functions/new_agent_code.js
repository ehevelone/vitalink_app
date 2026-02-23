// functions/new_agent_code.js
const db = require("./services/db");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

// ✅ Simple random alphanumeric generator
function generateUnlockCode() {
  return Array.from({ length: 8 }, () =>
    Math.floor(Math.random() * 36).toString(36).toUpperCase()
  ).join("");
}

exports.handler = async (event) => {
  try {

    let rsmId = null;
    const rsmToken = event.headers["x-rsm-token"];

    // ====================================================
    // 🔐 If RSM token exists → validate session
    // ====================================================
    if (rsmToken) {

      const client = await pool.connect();

      const rsmResult = await client.query(`
        SELECT id
        FROM rsms
        WHERE admin_session_token = $1
        AND role = 'rsm'
        AND admin_session_expires > NOW()
        LIMIT 1
      `, [rsmToken]);

      if (rsmResult.rows.length === 0) {
        client.release();
        return {
          statusCode: 401,
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ success: false, error: "Invalid RSM session" })
        };
      }

      rsmId = rsmResult.rows[0].id;
      client.release();
    }

    // ====================================================
    // 🔑 Generate unlock code
    // ====================================================
    const unlockCode = generateUnlockCode();

    // ====================================================
    // 🧱 Insert agent (NO promo logic anymore)
    // ====================================================
    const agentResult = await db.query(
      `
      INSERT INTO agents (unlock_code, active, role, rsm_id, created_at)
      VALUES ($1, FALSE, 'agent', $2, NOW())
      RETURNING id
      `,
      [unlockCode, rsmId]
    );

    const agentId = agentResult.rows[0].id;

    // ====================================================
    // 📱 JSON response for dashboard/app
    // ====================================================
    if (
      event.headers.accept &&
      event.headers.accept.includes("application/json")
    ) {
      return {
        statusCode: 200,
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          success: true,
          agentId,
          unlockCode
        }),
      };
    }

    // ====================================================
    // 🌐 Redirect fallback
    // ====================================================
    const deepLink = `vitalink://agent/onboard?code=${unlockCode}`;
    const playStoreLink =
      "https://play.google.com/store/apps/details?id=com.vitalink.app";

    return {
      statusCode: 302,
      headers: {
        Location: deepLink,
        "Content-Type": "text/html",
      },
      body: `
        <!DOCTYPE html>
        <html>
        <head>
          <meta charset="utf-8"/>
          <title>VitaLink Agent Unlock</title>
          <style>
            body { font-family: Arial; text-align: center; margin: 40px; }
            .code { font-size: 24px; font-weight: bold; color: #0077cc; margin: 20px 0; }
            a.button {
              display: inline-block; padding: 12px 20px; margin: 10px;
              background: #0077cc; color: white; text-decoration: none; border-radius: 6px;
            }
            a.secondary { background: #555; }
          </style>
        </head>
        <body>
          <h2>Welcome to VitaLink</h2>
          <p>Your unique agent unlock code:</p>
          <div class="code">${unlockCode}</div>
          <p>If the app is installed, it should open automatically.</p>
          <p>
            <a href="${deepLink}" class="button">Open in App</a>
            <a href="${playStoreLink}" class="button secondary">Download App</a>
          </p>
        </body>
        </html>
      `,
    };

  } catch (err) {
    console.error("❌ Error generating new agent code:", err);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ success: false, error: err.message }),
    };
  }
};