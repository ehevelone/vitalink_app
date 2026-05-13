// gotta change something 

const bcrypt = require("bcryptjs");
const { Pool } = require("pg");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

exports.handler = async function (event) {

  if (event.httpMethod === "OPTIONS") {
    return {
      statusCode: 200,
      headers: corsHeaders(),
      body: ""
    };
  }

  try {

    if (event.httpMethod !== "POST") {
      return {
        statusCode: 405,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Method Not Allowed" })
      };
    }

    const body = JSON.parse(event.body || "{}");

    const { email, password, step } = body;

    if (!email || !password) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Missing credentials" })
      };
    }

    const client = await pool.connect();

    // ✅ ALWAYS USE agents TABLE
    const result = await client.query(
      `
       SELECT id, crm_uuid, password_hash, TRIM(name) AS name, phone
       FROM agents
       WHERE LOWER(email) = LOWER($1)
       AND active = true
       ORDER BY id DESC
       LIMIT 1
      `,
      [email]
    );

    if (result.rows.length === 0) {

      client.release();

      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({
          success:false,
          error:"Unauthorized"
        })
      };

    }

    const user = result.rows[0];

    console.log("LOGIN USER:", user.id, user.name);

    const valid = await bcrypt.compare(
      password,
      user.password_hash
    );

    if (!valid) {

      client.release();

      return {
        statusCode: 403,
        headers: corsHeaders(),
        body: JSON.stringify({
          success:false,
          error:"Unauthorized"
        })
      };

    }

    // ---------------------------------------
    // 🔥 STEP 1 → SEND TO FIREBASE 2FA
    // ---------------------------------------
    if (!step || step === "login") {

      // ✅ NO PHONE → BYPASS 2FA
      if (!user.phone) {

        client.release();

        return {
          statusCode: 200,
          headers: corsHeaders(),
          body: JSON.stringify({
            step: "login_success",
            token: "dev-token",
            agent: {
              id: user.id,
              crm_uuid: user.crm_uuid,
              name: user.name || ""
            }
          })
        };

      }

      let phone = user.phone.replace(/\D/g, "");

      if (phone.length === 10) {

        phone = "+1" + phone;

      } else if (!phone.startsWith("+")) {

        phone = "+" + phone;

      }

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify({
          step: "firebase_2fa",
          phone,
          agent: {
            id: user.id,
            crm_uuid: user.crm_uuid,
            name: user.name || ""
          }
        })
      };

    }

    // ---------------------------------------
    // 🔥 STEP 2 → AFTER FIREBASE VERIFY
    // ---------------------------------------
    if (step === "verify") {

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify({
          step: "login_success",
          token: "dev-token",
          agent: {
            id: user.id,
            crm_uuid: user.crm_uuid,
            name: user.name || ""
          }
        })
      };

    }

    client.release();

    return {
      statusCode: 400,
      headers: corsHeaders(),
      body: JSON.stringify({
        success:false,
        error:"Invalid step"
      })
    };

  } catch (err) {

    console.error("agent-login error:", err);

    return {
      statusCode: 500,
      headers: corsHeaders(),
      body: JSON.stringify({
        success:false,
        error:"Server error"
      })
    };

  }

};

function corsHeaders() {

  return {
    "Access-Control-Allow-Origin": "https://myvitalink.app",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Allow-Methods": "POST, OPTIONS"
  };

}