// functions/export_agent_clients_csv.js
const db = require("./services/db");

function csvEscape(value) {
  if (value == null) return "";
  const s = String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

exports.handler = async (event) => {
  try {
    const agentId = event.queryStringParameters?.agent_id;
    if (!agentId) {
      return {
        statusCode: 400,
        headers: { "Content-Type": "text/plain" },
        body: "Missing agent_id",
      };
    }

    const result = await db.query(
      `
      SELECT
        a.email AS agent_email,
        u.email AS client_email,
        ARRAY_AGG(DISTINCT ud.platform) AS devices
      FROM agents a
      JOIN agent_users au ON au.agent_id = a.id
      JOIN users u ON u.id = au.user_id
      LEFT JOIN user_devices ud
        ON ud.user_id = u.id
       AND ud.agent_id = a.id
      WHERE a.id = $1
      GROUP BY a.email, u.email
      ORDER BY u.email;
      `,
      [agentId]
    );

    // CSV header
    let csv = "agent_email,client_email,devices\n";

    for (const row of result.rows) {
      csv += [
        csvEscape(row.agent_email),
        csvEscape(row.client_email),
        csvEscape((row.devices || []).join("|")),
      ].join(",") + "\n";
    }

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "text/csv",
        "Content-Disposition": `attachment; filename="agent_clients_${agentId}.csv"`,
      },
      body: csv,
    };
  } catch (err) {
    console.error("❌ export_agent_clients_csv error:", err);
    return {
      statusCode: 500,
      headers: { "Content-Type": "text/plain" },
      body: "Server error",
    };
  }
};
