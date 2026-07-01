// functions/confirm_reset.js
const db = require("./services/db");
const { hashPassword } = require("./services/passwords");

exports.handler = async (event) => {
  try {
    const { email, code, newPassword } = JSON.parse(event.body || "{}");

    if (!email || !code || !newPassword) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Missing fields" }),
      };
    }

    const result = await db.query("SELECT * FROM agents WHERE email=$1 AND reset_code=$2", [
      email,
      code,
    ]);

    if (!result.rows.length) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Invalid reset code" }),
      };
    }

    const agent = result.rows[0];
    if (new Date(agent.reset_expires) < new Date()) {
      return {
        statusCode: 400,
        body: JSON.stringify({ success: false, error: "Reset code expired" }),
      };
    }

    const hashed = await hashPassword(newPassword);

    await db.query(
      `UPDATE agents 
       SET password_hash=$1, reset_code=NULL, reset_expires=NULL 
       WHERE email=$2`,
      [hashed, email]
    );

    return {
      statusCode: 200,
      body: JSON.stringify({ success: true, message: "Password reset successful ✅" }),
    };
  } catch (err) {
    console.error("❌ confirm_reset error:", err);
    return {
      statusCode: 500,
      body: JSON.stringify({ success: false, error: err.message }),
    };
  }
};
