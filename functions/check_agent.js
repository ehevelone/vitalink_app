// functions/check_agent.js
const db = require("./services/db");
const bcrypt = require("bcryptjs");

const headers = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function ok(obj) {
  return {
    statusCode: 200,
    headers,
    body: JSON.stringify({ success: true, ...obj }),
  };
}

function fail(msg, code = 400, extra = {}) {
  return {
    statusCode: code,
    headers,
    body: JSON.stringify({ success: false, error: msg, ...extra }),
  };
}

exports.handler = async (event) => {
  try {
    // ✅ PREFLIGHT
    if (event.httpMethod === "OPTIONS") {
      return { statusCode: 200, headers, body: "" };
    }

    if (event.httpMethod !== "POST") {
      return fail("Method Not Allowed", 405);
    }

    const { email, password } = JSON.parse(event.body || "{}");

    if (!email || !password) {
      return fail("Missing email or password.");
    }

    const result = await db.query(
      "SELECT * FROM agents WHERE LOWER(email) = LOWER($1)",
      [email.trim()]
    );

    if (!result.rows.length) {
      return fail("No account found with this email.");
    }

    const agent = result.rows[0];

    if (!agent.password_hash) {
      return fail("Agent account not set up correctly.");
    }

    const isMatch = await bcrypt.compare(password, agent.password_hash);
    if (!isMatch) {
      return fail("Invalid password ❌");
    }

    // 🔥 FINAL ACCESS CONTROL (THIS IS THE IMPORTANT PART)

    const hasValidSubscription =
      agent.billing_owner !== null &&
      agent.subscription_status === "active";

    const isAllowed =
      agent.active === true || hasValidSubscription;

    if (!isAllowed) {
      return fail(
        "Access disabled",
        403,
        {
          requires_payment: true,
          message:
            "Your agency no longer covers your access. Activate your personal plan to continue.",
        }
      );
    }

    // ✅ SUCCESS
    return ok({
      agent: {
        id: agent.id,
        email: agent.email,
        name: agent.name,
        phone: agent.phone,
        npn: agent.npn,
        role: agent.role || "agent",
        active: agent.active,
        billing_owner: agent.billing_owner || null,
        subscription_status: agent.subscription_status || null,
      },
    });

  } catch (err) {
    console.error(err);
    return fail("Server error");
  }
};