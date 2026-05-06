const crypto = require("crypto");
const db = require("./services/db");

exports.handler = async (event) => {
  try {
    const token = event.queryStringParameters.token;

    if (!token) {
      return {
        statusCode: 400,
        body: "Missing token",
      };
    }

    const token_hash = crypto
      .createHash("sha256")
      .update(token)
      .digest("hex");

    // 🔍 Find invite
    const result = await db.query(
      `SELECT * FROM agent_invites 
       WHERE token_hash = $1 AND used = false`,
      [token_hash]
    );

    if (result.rows.length === 0) {
      return {
        statusCode: 400,
        body: "Invalid or expired invite",
      };
    }

    const invite = result.rows[0];

    // 🔥 Assign agent to user
    await db.query(
      `UPDATE users
       SET agent_id = $1
       WHERE LOWER(email) = LOWER($2)`,
      [invite.new_agent_id, invite.client_email]
    );

    // ✅ Mark invite used
    await db.query(
      `UPDATE agent_invites
       SET used = true
       WHERE id = $1`,
      [invite.id]
    );

    // 🔁 Redirect to success page
    return {
      statusCode: 302,
      headers: {
        Location: "https://myvitalink.app/success.html",
      },
    };

  } catch (err) {
    console.error("❌ accept-agent-invite error", err);

    return {
      statusCode: 500,
      body: "Error processing invite",
    };
  }
};