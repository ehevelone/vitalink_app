// @ts-nocheck

const { Pool } = require("pg");
const Stripe = require("stripe");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type, x-admin-session",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json"
};

function reply(statusCode, body) {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify(body)
  };
}

async function ensureBillingColumns(client) {
  await client.query(`
    ALTER TABLE rsms
    ADD COLUMN IF NOT EXISTS billing_active BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS stripe_subscription_item_id TEXT,
    ADD COLUMN IF NOT EXISTS subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS billing_mode TEXT DEFAULT 'office_paid'
  `);

  await client.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS linked_rsm_id UUID
  `);
}

function normalizeBillingMode(value) {
  return value === "agent_paid" ? "agent_paid" : "office_paid";
}

async function countBillableSeats(client, rsmId, billingMode) {
  if (billingMode === "agent_paid") {
    return 1;
  }

  const countResult = await client.query(
    `
    SELECT COUNT(*)::INT AS count
    FROM agents
    WHERE rsm_id = $1
      AND active = true
      AND linked_rsm_id IS DISTINCT FROM $1
    `,
    [rsmId]
  );

  return Number(countResult.rows[0]?.count || 0) + 1;
}

async function updateStripeQuantity(client, rsm, billableSeats) {
  if (!rsm.billing_active || !rsm.stripe_subscription_item_id?.startsWith("si_")) {
    return;
  }

  await stripe.subscriptionItems.update(
    rsm.stripe_subscription_item_id,
    {
      quantity: billableSeats
    }
  );

  console.log("Stripe quantity updated:", billableSeats);
}

exports.handler = async function (event) {
  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return reply(405, { success: false, error: "Method Not Allowed" });
  }

  const sessionToken = event.headers["x-admin-session"];

  if (!sessionToken) {
    return reply(401, { success: false, error: "Unauthorized" });
  }

  let body = {};

  try {
    body = JSON.parse(event.body || "{}");
  } catch {
    return reply(400, { success: false, error: "Invalid request body" });
  }

  const agentIdNum = Number(body.agentId);

  if (!body.agentId || Number.isNaN(agentIdNum)) {
    return reply(400, {
      success: false,
      error: "Invalid agentId"
    });
  }

  const client = await pool.connect();

  try {
    await ensureBillingColumns(client);

    const rsmCheck = await client.query(
      `
      SELECT
        id,
        email,
        billing_active,
        stripe_subscription_item_id,
        subscription_status,
        billing_mode
      FROM rsms
      WHERE admin_session_token = $1
        AND role = 'rsm'
        AND admin_session_expires > NOW()
      LIMIT 1
      `,
      [sessionToken]
    );

    if (!rsmCheck.rows.length) {
      return reply(401, { success: false, error: "Invalid session" });
    }

    const rsm = rsmCheck.rows[0];

    const current = await client.query(
      `
      SELECT id, active
      FROM agents
      WHERE id = $1
        AND rsm_id = $2
      LIMIT 1
      `,
      [agentIdNum, rsm.id]
    );

    if (!current.rows.length) {
      return reply(404, { success: false, error: "Agent not found" });
    }

    const currentlyActive = current.rows[0].active === true;
    const newActive = !currentlyActive;

    if (newActive && rsm.billing_active !== true) {
      return reply(402, {
        success: false,
        requires_billing: true,
        error: "Office billing must be active before activating agents."
      });
    }

    const billingMode = normalizeBillingMode(rsm.billing_mode);

    const update = await client.query(
      `
      UPDATE agents
      SET active = $1,
          billing_owner = CASE
            WHEN $1 = false THEN NULL
            WHEN $4 = 'agent_paid' THEN 'agent'
            ELSE 'rsm'
          END,
          subscription_status = CASE WHEN $1 = false THEN 'inactive' ELSE 'active' END
      WHERE id = $2
        AND rsm_id = $3
      RETURNING id, active, billing_owner, subscription_status
      `,
      [newActive, agentIdNum, rsm.id, billingMode]
    );

    const billableSeats = await countBillableSeats(client, rsm.id, billingMode);

    try {
      await updateStripeQuantity(client, rsm, billableSeats);
    } catch (stripeErr) {
      console.error("Stripe billing update failed:", stripeErr.message);
    }

    const ip = event.headers["x-forwarded-for"] || "unknown";
    const newStatus = newActive ? "activated" : "deactivated";

    await client.query(
      `
      INSERT INTO admin_logs (admin_id, action, target, ip)
      VALUES ($1,$2,$3,$4)
      `,
      [
        rsm.id,
        "toggle_agent",
        `agent:${agentIdNum}:${newStatus}`,
        ip
      ]
    );

    return reply(200, {
      success: true,
      agent: update.rows[0],
      billed_quantity: billableSeats,
      billing_mode: billingMode
    });

  } catch (err) {
    console.error("toggle-agent error:", err);

    return reply(500, {
      success: false,
      error: "Server error"
    });

  } finally {
    client.release();
  }
};
