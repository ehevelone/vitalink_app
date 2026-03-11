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
    return { statusCode: 200, headers: corsHeaders, body: "" };
  }

  if (event.httpMethod !== "POST") {
    return { statusCode: 405, headers: corsHeaders, body: "Method Not Allowed" };
  }

  try {

    const { name, email } = JSON.parse(event.body || "{}");

    if (!name || !email) {
      return {
        statusCode: 400,
        headers: corsHeaders,
        body: "Missing fields"
      };
    }

    const client = await pool.connect();

    const result = await client.query(
      `UPDATE activation_codes
       SET name = $1, email = $2
       WHERE id = (
         SELECT id
         FROM activation_codes
         ORDER BY created_at DESC
         LIMIT 1
       )
       RETURNING code`,
      [name, email]
    );

    client.release();

    if (result.rows.length === 0) {
      return {
        statusCode: 404,
        headers: corsHeaders,
        body: "Activation not found"
      };
    }

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        code: result.rows[0].code
      })
    };

  } catch (err) {

    console.error("register purchase error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders,
      body: "Server error"
    };

  }

};