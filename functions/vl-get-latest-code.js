const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "GET, OPTIONS"
};

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders,
      body: ""
    };
  }

  try {

    const params = event.queryStringParameters || {};
    const sessionId = params.session_id;

    console.log("Session requested:", sessionId);

    if (!sessionId) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Missing session id" })
      };
    }

    const client = await pool.connect();

    const result = await client.query(
      `SELECT code
       FROM activation_codes
       WHERE stripe_session = $1
       LIMIT 1`,
      [sessionId]
    );

    client.release();

    console.log("DB result:", result.rows);

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: corsHeaders,
        body: JSON.stringify({ error: "Activation code not found" })
      };
    }

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ code: result.rows[0].code })
    };

  } catch (err) {

    console.error("Activation lookup error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ error: "Server error" })
    };

  }

};