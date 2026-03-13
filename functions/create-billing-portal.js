const Stripe = require("stripe");
const { Pool } = require("pg");

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

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: "Method Not Allowed"
    };
  }

  const client = await pool.connect();

  try {

    const sessionToken = event.headers["x-admin-session"];

    if (!sessionToken) {
      return {
        statusCode: 401,
        headers: corsHeaders,
        body: "Unauthorized"
      };
    }

    /* VERIFY RSM SESSION */

    const rsm = await client.query(
      `
      SELECT id,email,stripe_customer_id
      FROM rsms
      WHERE admin_session_token = $1
      AND admin_session_expires > NOW()
      LIMIT 1
      `,
      [sessionToken]
    );

    if (rsm.rows.length === 0) {
      return {
        statusCode: 401,
        headers: corsHeaders,
        body: "Invalid session"
      };
    }

    const rsmData = rsm.rows[0];

    /* EXISTING CUSTOMER → BILLING PORTAL */

    if (rsmData.stripe_customer_id) {

      const portalSession = await stripe.billingPortal.sessions.create({
        customer: rsmData.stripe_customer_id,

        /* FIXED PATH */
        return_url: "https://myvitalink.app/core-node/rsm_report.html"
      });

      return {
        statusCode: 200,
        headers: corsHeaders,
        body: JSON.stringify({ url: portalSession.url })
      };
    }

    /* FIRST TIME → CREATE CHECKOUT */

    const checkoutSession = await stripe.checkout.sessions.create({

      mode: "subscription",

      customer_email: rsmData.email,

      line_items: [
        {
          price: process.env.STRIPE_RSM_PRICE_ID,
          quantity: 1
        }
      ],

      /* FIXED PATH */
      success_url:
        "https://myvitalink.app/core-node/rsm_report.html?billing=success",

      /* FIXED PATH */
      cancel_url:
        "https://myvitalink.app/core-node/rsm_report.html?billing=cancel",

      metadata: {
        rsm_id: rsmData.id
      }

    });

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ url: checkoutSession.url })
    };

  } catch (err) {

    console.error("Billing error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: err.message })
    };

  } finally {
    client.release();
  }

};