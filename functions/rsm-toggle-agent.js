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
    ADD COLUMN IF NOT EXISTS subscription_status TEXT
  `);
}

async function countActiveAgents(client, rsmId) {
  const countResult = await client.query(
    `
    SELECT COUNT(*)::INT AS count
    FROM agents
    WHERE rsm_id = $1
      AND active = true
    `,
    [rsmId]
  );

  return Number(countResult.rows[0]?.count || 0);
}

async function updateStripeQuantity(client, rsm, activeCount) {
  if (!rsm.billing_active || !rsm.stripe_subscription_item_id?.startsWith("si_")) {
    return;
  }

  if (activeCount === 0) {
    const subItem =
      await stripe.subscriptionItems.retrieve(rsm.stripe_subscription_item_id);

    await stripe.subscriptions.cancel(subItem.subscription);

    await client.query(
      `
      UPDATE rsms
      SET billing_active = false,
          stripe_subscription_item_id = NULL,
          subscription_status = 'canceled'
      WHERE id = $1
      `,
      [rsm.id]
    );

    console.log("Stripe subscription canceled for RSM:", rsm.id);
    return;
  }

  await stripe.subscriptionItems.update(
    rsm.stripe_subscription_item_id,
    {
      quantity: activeCount
    }
  );

  console.log("Stripe quantity updated:", activeCount);
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
        subscription_status
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

    const update = await client.query(
      `
      UPDATE agents
      SET active = $1,
          billing_owner = CASE WHEN $1 = false THEN NULL ELSE 'rsm' END,
          subscription_status = CASE WHEN $1 = false THEN 'inactive' ELSE 'active' END
      WHERE id = $2
        AND rsm_id = $3
      RETURNING id, active, billing_owner, subscription_status
      `,
      [newActive, agentIdNum, rsm.id]
    );

    const activeCount = await countActiveAgents(client, rsm.id);

    try {
      await updateStripeQuantity(client, rsm, activeCount);
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
      active_agents: activeCount
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
