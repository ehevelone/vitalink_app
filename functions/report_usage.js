// functions/report_usage.js
const db = require("./services/db");
const { requireAdmin } = require("./_adminAuth");


function ok(obj) {
  return {
    statusCode: 200,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: true, ...obj }),
  };
}

function fail(msg) {
  return {
    statusCode: 400,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ success: false, error: msg }),
  };
}

exports.handler = async (event) => {
  try {
    const auth = await requireAdmin(event);

    if (auth.error) {
      return fail("Unauthorized ❌");
    }

    // 📊 Lifetime usage
    const lifetimeResult = await db.query(`
      SELECT a.id, a.email, COUNT(r.id) AS total_uses
      FROM agents a
      LEFT JOIN redemptions r ON a.id = r.agent_id
      GROUP BY a.id, a.email
      ORDER BY total_uses DESC
    `);

    // 📊 Monthly usage (current calendar month, based on redeemed_at)
    const monthlyResult = await db.query(`
      SELECT a.id, a.email, COUNT(r.id) AS monthly_uses
      FROM agents a
      LEFT JOIN redemptions r 
        ON a.id = r.agent_id 
       AND date_trunc('month', r.redeemed_at) = date_trunc('month', CURRENT_DATE)
      GROUP BY a.id, a.email
      ORDER BY monthly_uses DESC
    `);

    return ok({
      message: "Usage report generated ✅",
      lifetime: lifetimeResult.rows,
      monthly: monthlyResult.rows,
    });
  } catch (err) {
    console.error("❌ report_usage error:", err);
    return {
      statusCode: 500,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        success: false,
        error: "Server error: " + err.message,
      }),
    };
  }
};
