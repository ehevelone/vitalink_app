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

    // STEP 1: find agent_id from unlock_code
    const agent = await db.query(
      `
      SELECT id
      FROM agents
      WHERE unlock_code = $1
      `,
      [unlockCode]
    );

    if (agent.rows.length === 0) {
      return {
        statusCode: 404,
        body: JSON.stringify({ error: "Agent not found" })
      };
    }

    const agentId = agent.rows[0].id;

    // STEP 2: get users tied to that agent
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
      WHERE agent_id = $1
      ORDER BY created_at DESC
      `,
      [agentId]
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