const db = require("./services/db");

exports.handler = async (event) => {

  if (event.httpMethod !== "POST") {
    return {
      statusCode: 405,
      body: "Method Not Allowed"
    };
  }

  try {

    const body = JSON.parse(event.body);
    const unlockCode = body.unlock_code;

    if (!unlockCode) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: "Missing unlock code" })
      };
    }

    const result = await db.query(
      `
      SELECT
        id,
        first_name,
        last_name,
        dob,
        active,
        created_at
      FROM users
      WHERE agent_code = $1
      ORDER BY created_at DESC
      `,
      [unlockCode]
    );

    return {
      statusCode: 200,
      body: JSON.stringify({
        clients: result.rows
      })
    };

  } catch (err) {

    console.error("Agent clients error:", err);

    return {
      statusCode: 500,
      body: JSON.stringify({
        error: "Server error"
      })
    };

  }

};