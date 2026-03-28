const db = require("./services/db");

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body);

    const { user_id, items } = body;

    if (!user_id || !items) {
      return {
        statusCode: 400,
        body: "Missing data",
      };
    }

    const result = await db.query(
      `
      INSERT INTO order_requests (user_id, items, status)
      VALUES ($1, $2, 'pending')
      RETURNING id
      `,
      [user_id, JSON.stringify(items)]
    );

    const request_id = result.rows[0].id;

    return {
      statusCode: 200,
      body: JSON.stringify({ request_id }),
    };
  } catch (err) {
    console.error(err);
    return {
      statusCode: 500,
      body: "Server error",
    };
  }
};