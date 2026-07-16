// functions/sync-stripe-agent-count.js

const { Pool } = require("pg");
const Stripe = require("stripe");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

function normalizeBillingMode(value) {
  return value === "agent_paid" ? "agent_paid" : "office_paid";
}

exports.handler = async () => {

  const client = await pool.connect();

  try {

    console.log("Starting Stripe agent billing sync");

    // Get all active RSM subscriptions
    const rsms = await client.query(
      `
      SELECT id, stripe_subscription_item_id, billing_mode
      FROM rsms
      WHERE billing_active = true
      AND stripe_subscription_item_id IS NOT NULL
      `
    );

    console.log(`Found ${rsms.rows.length} offices to sync`);

    for (const rsm of rsms.rows) {

      const billingMode = normalizeBillingMode(rsm.billing_mode);

      // Count active non-self agents. The RSM always counts as one billable seat
      // unless agents are paying individually.
      const countResult = await client.query(
        `
        SELECT COUNT(*)
        FROM agents
        WHERE rsm_id = $1
        AND active = true
        AND linked_rsm_id IS DISTINCT FROM $1
        `,
        [rsm.id]
      );

      const activeAgents = parseInt(countResult.rows[0].count);
      const billableSeats = billingMode === "agent_paid"
        ? 1
        : activeAgents + 1;

      console.log(`RSM ${rsm.id} billable seats: ${billableSeats}`);

      try {

        // Update Stripe quantity
        await stripe.subscriptionItems.update(
          rsm.stripe_subscription_item_id,
          {
            quantity: billableSeats
          }
        );

        console.log(`Stripe quantity synced -> ${billableSeats}`);

      } catch (stripeErr) {

        console.error("Stripe sync error:", stripeErr.message);

      }

    }

    console.log("Stripe sync complete");

    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        synced: rsms.rows.length
      })
    };

  } catch (err) {

    console.error("Stripe sync failure:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({
        success: false,
        error: err.message
      })
    };

  } finally {

    client.release();

  }

};
