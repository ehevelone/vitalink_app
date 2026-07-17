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

async function ensureBillingColumns(client) {
  await client.query(`
    ALTER TABLE rsms
    ADD COLUMN IF NOT EXISTS billing_active BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS billing_mode TEXT DEFAULT 'office_paid',
    ADD COLUMN IF NOT EXISTS billing_interval TEXT DEFAULT 'monthly',
    ADD COLUMN IF NOT EXISTS pricing_tier TEXT DEFAULT 'founders'
  `);

  await client.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS linked_rsm_id UUID
  `);
}

function normalizeBillingMode(value) {
  return value === "agent_paid" ? "agent_paid" : "office_paid";
}

function normalizeBillingInterval(value) {
  return value === "annual" ? "annual" : "monthly";
}

function normalizePricingTier(value) {
  return value === "regular" ? "regular" : "founders";
}

function isAdminOverride(...values) {
  return values.some((value) =>
    String(value || "").trim().toLowerCase() === "admin_override"
  );
}

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

    await ensureBillingColumns(client);

    // 🔐 Validate session + get billing status + invite code
    const rsmResult = await client.query(`
      SELECT
        id,
        billing_active,
        invite_code,
        subscription_status,
        current_period_end,
        billing_mode,
        billing_interval,
        pricing_tier,
        stripe_customer_id,
        stripe_subscription_id,
        stripe_subscription_item_id
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
    const rsm = rsmResult.rows[0];
    const rsmAccessOverride = isAdminOverride(
      rsm.subscription_status,
      rsm.stripe_customer_id,
      rsm.stripe_subscription_id,
      rsm.stripe_subscription_item_id
    );
    const billingActive = rsm.billing_active === true || rsmAccessOverride;
    const inviteCode = rsmResult.rows[0].invite_code;
    const subscriptionStatus = rsmResult.rows[0].subscription_status;
    const currentPeriodEnd = rsmResult.rows[0].current_period_end;
    const billingMode = normalizeBillingMode(rsmResult.rows[0].billing_mode);
    const billingInterval = normalizeBillingInterval(rsmResult.rows[0].billing_interval);
    const pricingTier = normalizePricingTier(rsmResult.rows[0].pricing_tier);

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
      AND linked_rsm_id IS DISTINCT FROM $1
    `, [rsmId]);

    client.release();

    const activeNonSelfAgents = Number(count.rows[0].count);
    const billableSeats = billingMode === "agent_paid"
      ? 1
      : activeNonSelfAgents + 1;
    const seatPrice = pricingTier === "regular" ? 20 : 10;
    const billingEstimate = billingInterval === "annual"
      ? billableSeats * seatPrice * 12
      : billableSeats * seatPrice;

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        billing_active: billingActive,
        admin_override: rsmAccessOverride,
        billing_mode: billingMode,
        billing_interval: billingInterval,
        pricing_tier: pricingTier,
        subscription_status: subscriptionStatus,
        current_period_end: currentPeriodEnd,
        invite_code: inviteCode,
        active_agents: activeNonSelfAgents,
        billable_seats: billableSeats,
        billing_estimate: billingEstimate,
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
