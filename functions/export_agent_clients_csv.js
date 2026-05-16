const db = require("./services/db");
const { requireAdminOrRsm } = require("./_adminAuth");
const { verifyAgentSession } = require("./services/agent-auth");

// 🔥 FORCE single-line + safe CSV
function csvEscape(value) {
  if (value == null) return "";

  let s = String(value)
    .replace(/[\r\n]+/g, " ")   // remove ALL line breaks
    .replace(/\s+/g, " ")       // collapse spaces
    .trim();

  s = s.replace(/"/g, '""');    // escape quotes

  return `"${s}"`;              // always wrap
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

    const agentSessionToken =
      event.headers["x-agent-session"] ||
      event.headers["X-Agent-Session"];

    let authorized = false;

    if (agentSessionToken) {
      const agent = await verifyAgentSession({
        agentId,
        token: agentSessionToken,
      });
      authorized = Boolean(agent);
    } else {
      const auth = await requireAdminOrRsm(event);

      if (!auth.error && auth.user.role === "admin") {
        authorized = true;
      }

      if (!auth.error && auth.user.role === "rsm") {
        const owner = await db.query(
          "SELECT id FROM agents WHERE id = $1 AND rsm_id = $2 LIMIT 1",
          [agentId, auth.user.id]
        );
        authorized = owner.rows.length > 0;
      }
    }

    if (!authorized) {
      return {
        statusCode: 403,
        headers: { "Content-Type": "text/plain" },
        body: "Unauthorized",
      };
    }

    // 🔹 MAIN CLIENT QUERY
    const result = await db.query(
      `
      SELECT
        a.email AS agent_email,
        u.id AS user_id,
        u.email AS client_email,
        p.first_name,
        p.last_name,
        p.phone,
        p.address,
        p.city,
        p.state,
        p.zip,
        p.dob,
        p.gender
      FROM agents a
      JOIN agent_users au ON au.agent_id = a.id
      JOIN users u ON u.id = au.user_id
      LEFT JOIN profiles p ON p.user_id = u.id
      WHERE a.id = $1
      ORDER BY u.email;
      `,
      [agentId]
    );

    // 🔹 MEDICATIONS
    const medsRes = await db.query(`
      SELECT user_id, name, dosage
      FROM medications
    `);

    // 🔹 DOCTORS
    const doctorsRes = await db.query(`
      SELECT user_id, name, specialty, phone
      FROM doctors
    `);

    // 🔹 Build lookup maps
    const medsMap = {};
    for (const row of medsRes.rows) {
      if (!medsMap[row.user_id]) medsMap[row.user_id] = [];
      medsMap[row.user_id].push(
        `${row.name || ""} ${row.dosage || ""}`.trim()
      );
    }

    const doctorsMap = {};
    for (const row of doctorsRes.rows) {
      if (!doctorsMap[row.user_id]) doctorsMap[row.user_id] = [];
      doctorsMap[row.user_id].push(
        `${row.name || ""}${row.specialty ? " - " + row.specialty : ""}${
          row.phone ? " - " + row.phone : ""
        }`
      );
    }

    // 🔥 CSV HEADER (CRM SAFE)
    let csv =
      "first_name,last_name,phone,email,address,city,state,zip,dob,gender,medications,doctors,notes,source\n";

    // 🔹 Build rows
    for (const row of result.rows) {
      const meds = (medsMap[row.user_id] || []).join("; ");
      const doctors = (doctorsMap[row.user_id] || []).join("; ");

      // 🔥 SINGLE LINE NOTES (NO BREAKS)
      const notes = `VitaLink Client | Meds: ${meds} | Doctors: ${doctors}`;

      csv += [
        csvEscape(row.first_name),
        csvEscape(row.last_name),
        csvEscape(row.phone),
        csvEscape(row.client_email),
        csvEscape(row.address),
        csvEscape(row.city),
        csvEscape(row.state),
        csvEscape(row.zip),
        csvEscape(row.dob),
        csvEscape(row.gender),
        csvEscape(meds),
        csvEscape(doctors),
        csvEscape(notes),
        "VitaLink",
      ].join(",") + "\n";
    }

    return {
      statusCode: 200,
      headers: {
        "Content-Type": "text/csv",
        "Content-Disposition": `attachment; filename="clients_${agentId}.csv"`,
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
