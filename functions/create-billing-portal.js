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
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: ""
    };
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

    const rsmResult = await client.query(
      `
      SELECT id,email,stripe_customer_id
      FROM rsms
      WHERE admin_session_token = $1
      AND admin_session_expires > NOW()
      LIMIT 1
      `,
      [sessionToken]
    );

    if (rsmResult.rows.length === 0) {
      return {
        statusCode: 401,
        headers: corsHeaders,
        body: "Invalid session"
      };
    }

    const rsm = rsmResult.rows[0];

    /* EXISTING CUSTOMER → BILLING PORTAL */

    if (rsm.stripe_customer_id) {

      const portalSession = await stripe.billingPortal.sessions.create({
        customer: rsm.stripe_customer_id,
        return_url: "https://myvitalink.app/rsm_report.html"
      });

      return {
        statusCode: 200,
        headers: corsHeaders,
        body: JSON.stringify({
          url: portalSession.url
        })
      };

    }

    /* NO CUSTOMER → CREATE CHECKOUT */

    const checkoutSession = await stripe.checkout.sessions.create({

      mode: "subscription",

      customer_email: rsm.email,

      line_items: [
        {
          price: process.env.STRIPE_ACTIVATION_PRICE_ID,
          quantity: 1
        }
      ],

      success_url:
        "https://myvitalink.app/rsm_report.html?billing=success",

      cancel_url:
        "https://myvitalink.app/rsm_report.html?billing=cancel",

    });

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        url: checkoutSession.url
      })
    };

  } catch (err) {

    console.error("Billing error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({
        error: err.message
      })
    };

  } finally {
    client.release();
  }

};