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

  if (event.httpMethod !== "GET") {
    return {
      statusCode: 405,
      headers: corsHeaders,
      body: "Method Not Allowed"
    };
  }

  try {

    const client = await pool.connect();

    const result = await client.query(
      `SELECT code
       FROM activation_codes
       ORDER BY created_at DESC
       LIMIT 1`
    );

    client.release();

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: corsHeaders,
        body: JSON.stringify({ code: null })
      };
    }

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({ code: result.rows[0].code })
    };

  } catch (err) {

    console.error("Fetch activation code error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };

  }

};