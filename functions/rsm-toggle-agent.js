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
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  try {

    const sessionToken = event.headers["x-admin-session"];
    const ip = event.headers["x-forwarded-for"] || "unknown";

    if (!sessionToken) {
      return { statusCode: 401, headers: corsHeaders, body: "Unauthorized" };
    }

    const { agentId } = JSON.parse(event.body || "{}");

    if (!agentId) {
      return { statusCode: 400, headers: corsHeaders, body: "Missing agentId" };
    }

    const client = await pool.connect();

    // Verify RSM session
    const rsmCheck = await client.query(
      `SELECT id, email, stripe_subscription_id, stripe_subscription_item_id
       FROM rsms
       WHERE admin_session_token = $1
       AND admin_session_expires > NOW()
       LIMIT 1`,
      [sessionToken]
    );

    if (rsmCheck.rows.length === 0) {
      client.release();
      return { statusCode: 401, headers: corsHeaders, body: "Invalid session" };
    }

    const rsm = rsmCheck.rows[0];

    // Toggle agent active status
    const update = await client.query(
      `UPDATE agents
       SET active = NOT active
       WHERE id = $1
       RETURNING id, active`,
      [agentId]
    );

    if (update.rows.length === 0) {
      client.release();
      return { statusCode: 404, headers: corsHeaders, body: "Agent not found" };
    }

    const newStatus = update.rows[0].active ? "activated" : "deactivated";

    // Count active agents
    const countResult = await client.query(
      `SELECT COUNT(*)
       FROM agents
       WHERE rsm_id = $1
       AND active = true`,
      [rsm.id]
    );

    const activeCount = parseInt(countResult.rows[0].count);

    console.log("Active agents:", activeCount);

    // Update Stripe quantity
    if (rsm.stripe_subscription_item_id) {

      await stripe.subscriptionItems.update(
        rsm.stripe_subscription_item_id,
        {
          quantity: activeCount
        }
      );

      console.log("Stripe quantity updated:", activeCount);

    }

    // Log action
    await client.query(
      `INSERT INTO admin_logs (admin_id, action, target, ip)
       VALUES ($1,$2,$3,$4)`,
      [
        rsm.id,
        "toggle_agent",
        `agent:${agentId}:${newStatus}`,
        ip
      ]
    );

    client.release();

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        agent: update.rows[0],
        active_agents: activeCount
      })
    };

  } catch (err) {
    console.error("toggle-agent error:", err);
    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };
  }

};