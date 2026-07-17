// gotta change something 

const crypto = require("crypto");
const { Pool } = require("pg");
const { hashPassword, verifyPassword } = require("./services/passwords");

const pool = new Pool({
  connectionString: process.env.SUPABASE_URL,
  ssl: { rejectUnauthorized: false }
});

async function ensureAgentSessionColumns(client) {
  await client.query(`
    ALTER TABLE agents
    ADD COLUMN IF NOT EXISTS session_token TEXT,
    ADD COLUMN IF NOT EXISTS session_expires TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS crm_subscription_status TEXT,
    ADD COLUMN IF NOT EXISTS crm_subscription_valid BOOLEAN DEFAULT false,
    ADD COLUMN IF NOT EXISTS crm_stripe_customer_id TEXT,
    ADD COLUMN IF NOT EXISTS crm_stripe_subscription_id TEXT
  `);
}

async function createAgentSession(client, agentId) {
  const token = crypto.randomBytes(32).toString("hex");
  const expires = new Date(Date.now() + 8 * 60 * 60 * 1000);

  await client.query(
    `
    UPDATE agents
    SET session_token = $1,
        session_expires = $2
    WHERE id = $3
    `,
    [token, expires, agentId]
  );

  return token;
}

function isTestAgent(user) {
  return String(user.email || "").trim().toLowerCase() ===
    "agent-test@example.com";
}

function isAdminOverride(...values) {
  return values.some((value) =>
    String(value || "").trim().toLowerCase() === "admin_override" ||
    String(value || "").trim().toLowerCase() === "admin_manual_access"
  );
}

function hasCrmAccess(user) {
  return isAdminOverride(
      user.crm_subscription_status,
      user.crm_stripe_customer_id,
      user.crm_stripe_subscription_id
    ) ||
    user.crm_subscription_valid === true ||
    user.crm_subscription_status === "active" ||
    user.crm_subscription_status === "trialing";
}

function loginSuccessBody(user, token, product) {
  const crmActive = hasCrmAccess(user);

  return {
    step: "login_success",
    token,
    crm_access: product === "crm" ? crmActive : undefined,
    requires_crm_payment:
      product === "crm" ? !crmActive : undefined,
    agent: {
      id: user.id,
      crm_uuid: user.crm_uuid,
      email: user.email,
      name: user.name || ""
    }
  };
}

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

    const { email, password, step, product } = body;

    if (!email || !password) {
      return {
        statusCode: 400,
        headers: corsHeaders(),
        body: JSON.stringify({ success:false, error:"Missing credentials" })
      };
    }

    const client = await pool.connect();
    await ensureAgentSessionColumns(client);

    // ✅ ALWAYS USE agents TABLE
    const result = await client.query(
      `
       SELECT
         id,
         crm_uuid,
         email,
         password_hash,
         TRIM(name) AS name,
         phone,
         crm_subscription_status,
         crm_subscription_valid,
         crm_stripe_customer_id,
         crm_stripe_subscription_id
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

    const passwordCheck = await verifyPassword(password, user.password_hash);
    const valid = passwordCheck.valid;

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

    if (passwordCheck.legacy) {
      await client.query(
        "UPDATE agents SET password_hash = $1 WHERE id = $2",
        [await hashPassword(password), user.id]
      );
    }

    if (isTestAgent(user)) {

      const token = await createAgentSession(client, user.id);

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify(loginSuccessBody(user, token, product))
      };

    }

    // ---------------------------------------
    // 🔥 STEP 1 → SEND TO FIREBASE 2FA
    // ---------------------------------------
    if (!step || step === "login") {

      // ✅ NO PHONE → BYPASS 2FA
      if (!user.phone) {

        const token = await createAgentSession(client, user.id);

        client.release();

        return {
          statusCode: 200,
          headers: corsHeaders(),
          body: JSON.stringify(loginSuccessBody(user, token, product))
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
            email: user.email,
            name: user.name || ""
          }
        })
      };

    }

    // ---------------------------------------
    // 🔥 STEP 2 → AFTER FIREBASE VERIFY
    // ---------------------------------------
    if (step === "verify") {

      const token = await createAgentSession(client, user.id);

      client.release();

      return {
        statusCode: 200,
        headers: corsHeaders(),
        body: JSON.stringify(loginSuccessBody(user, token, product))
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
