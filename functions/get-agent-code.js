const Stripe = require("stripe");
const db = require("./services/db");

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://myvitalink.app",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

exports.handler = async (event) => {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: ""
    };
  }

  try {

    const sessionId = event.queryStringParameters?.session_id;

    if (!sessionId) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: JSON.stringify({
          error: "Missing session_id"
        })
      };
    }

    // Retrieve Stripe checkout session
    const session = await stripe.checkout.sessions.retrieve(sessionId);

    const customerId = session.customer;

    if (!customerId) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: JSON.stringify({
          error: "Missing Stripe customer ID"
        })
      };
    }

    // Lookup agent by Stripe customer
    const result = await db.query(
      `
      SELECT unlock_code
      FROM agents
      WHERE stripe_customer_id = $1
      LIMIT 1
      `,
      [customerId]
    );

    if (!result.rows.length) {
      return {
        statusCode: 404,
        headers: corsHeaders,
        body: JSON.stringify({
          error: "Agent not found"
        })
      };
    }

    const code = result.rows[0].unlock_code;

    if (!code) {
      return {
        statusCode: 404,
        headers: corsHeaders,
        body: JSON.stringify({
          error: "Unlock code not generated yet"
        })
      };
    }

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        unlock_code: code
      })
    };

  } catch (err) {

    console.error("Get agent code error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({
        error: "Server error"
      })
    };

  }

};