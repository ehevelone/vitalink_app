// functions/rsm-summary-report.js
const { Pool } = require("pg");
const PDFDocument = require("pdfkit");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "GET") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  try {

    const token = event.headers["x-admin-session"];

    if (!token) {
      return { statusCode: 401, headers: corsHeaders, body: "Missing token" };
    }

    const client = await pool.connect();

    // 🔐 Validate session + get billing status + invite code
    const rsmResult = await client.query(`
      SELECT id, billing_active, invite_code
      FROM rsms
      WHERE admin_session_token = $1
      AND role = 'rsm'
      AND admin_session_expires > NOW()
      LIMIT 1
    `, [token]);

    if (rsmResult.rows.length === 0) {
      client.release();
      return { statusCode: 401, headers: corsHeaders, body: "Invalid session" };
    }

    const rsmId = rsmResult.rows[0].id;
    const billingActive = rsmResult.rows[0].billing_active;
    const inviteCode = rsmResult.rows[0].invite_code;

    const { search, download, id } = event.queryStringParameters || {};

    // =========================================================
    // 📄 SINGLE AGENT PDF
    // =========================================================
    if (download === "agent" && id) {

      const agent = await client.query(`
        SELECT name, email, active, created_at
        FROM agents
        WHERE id = $1 AND rsm_id = $2
        LIMIT 1
      `, [id, rsmId]);

      client.release();

      if (agent.rows.length === 0) {
        return { statusCode: 404, headers: corsHeaders, body: "Not found" };
      }

      const a = agent.rows[0];

      const doc = new PDFDocument({ margin: 50 });
      const buffers = [];
      doc.on("data", buffers.push.bind(buffers));

      doc.fontSize(18).text("Agent Report", { align: "center" });
      doc.moveDown();

      doc.fontSize(12);
      doc.text(`Name: ${a.name || ""}`);
      doc.text(`Email: ${a.email}`);
      doc.text(`Status: ${a.active ? "Active" : "Inactive"}`);
      doc.text(`Created: ${a.created_at}`);

      doc.end();

      await new Promise(resolve => doc.on("end", resolve));
      const pdf = Buffer.concat(buffers);

      return {
        statusCode: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/pdf",
          "Content-Disposition": `attachment; filename=agent_${id}.pdf`
        },
        body: pdf.toString("base64"),
        isBase64Encoded: true
      };
    }

    // =========================================================
    // 📊 FULL ROSTER PDF
    // =========================================================
    if (download === "roster") {

      const agents = await client.query(`
        SELECT name, email, active
        FROM agents
        WHERE rsm_id = $1
        ORDER BY created_at DESC
      `, [rsmId]);

      client.release();

      const doc = new PDFDocument({ margin: 40 });
      const buffers = [];
      doc.on("data", buffers.push.bind(buffers));

      doc.fontSize(18).text("RSM Agent Roster", { align: "center" });
      doc.moveDown();

      doc.fontSize(12);

      agents.rows.forEach(a => {
        doc.text(
          `${a.name || ""}  |  ${a.email}  |  ${a.active ? "Active" : "Inactive"}`
        );
      });

      doc.end();

      await new Promise(resolve => doc.on("end", resolve));
      const pdf = Buffer.concat(buffers);

      return {
        statusCode: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/pdf",
          "Content-Disposition": "attachment; filename=rsm_roster.pdf"
        },
        body: pdf.toString("base64"),
        isBase64Encoded: true
      };
    }

    // =========================================================
    // 🔎 NORMAL UI JSON RESPONSE
    // =========================================================

    const agents = await client.query(`
      SELECT id, name, email, active, created_at
      FROM agents
      WHERE rsm_id = $1
      AND (
        $2 = '' OR
        LOWER(name) LIKE LOWER($2) OR
        LOWER(email) LIKE LOWER($2)
      )
      ORDER BY created_at DESC
    `, [rsmId, `%${search || ""}%`]);

    const count = await client.query(`
      SELECT COUNT(*)
      FROM agents
      WHERE rsm_id = $1
      AND active = true
    `, [rsmId]);

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        billing_active: billingActive,
        invite_code: inviteCode,
        active_agents: Number(count.rows[0].count),
        agents: agents.rows
      })
    };

  } catch (err) {
    console.error("rsm-summary-report error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }
};