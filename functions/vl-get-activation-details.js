const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const SITE = "https://myvitalink.app";

const corsHeaders = {
  "Access-Control-Allow-Origin": SITE,
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};

exports.handler = async function (event) {

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
      body: JSON.stringify({ success:false })
    };
  }

  try {

    const body = JSON.parse(event.body || "{}");
    const code = body.code?.toUpperCase().trim();

    if (!code) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: JSON.stringify({ success:false })
      };
    }

    const client = await pool.connect();

    const result = await client.query(
      `
      SELECT full_name, email
      FROM activation_codes
      WHERE code = $1
      LIMIT 1
      `,
      [code]
    );

    client.release();

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: corsHeaders,
        body: JSON.stringify({ success:false })
      };
    }

    const row = result.rows[0];

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        success: true,
        name: row.full_name,
        email: row.email
      })
    };

  } catch (err) {

    console.error("lookup_activation error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: JSON.stringify({ success:false })
    };

  }

};